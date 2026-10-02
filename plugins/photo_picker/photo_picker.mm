/*************************************************************************/
/*  photo_picker.cpp                                                     */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2021 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "photo_picker.h"

#include "core/class_db.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

#import <dispatch/dispatch.h>

#if VERSION_MAJOR == 4
#if VERSION_MINOR >= 6
#import "drivers/apple_embedded/app_delegate_service.h"
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/godot_view_controller.h"
#elif VERSION_MINOR >= 5
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/view_controller.h"
#else
#import "platform/ios/app_delegate.h"
#import "platform/ios/view_controller.h"
#endif
#else
#import "platform/iphone/app_delegate.h"
#import "platform/iphone/view_controller.h"
#endif

PhotoPicker *instance = NULL;

static const NSInteger MAX_SELECTION_LIMIT = 12;


/*************************************************************************/
/* GodotPhotoPicker                                                      */
/*************************************************************************/

@interface GodotPhotoPicker : NSObject <PHPickerViewControllerDelegate>
@end


@implementation GodotPhotoPicker


- (void)presentMultiple:(NSInteger)selectionLimit {

	dispatch_async(dispatch_get_main_queue(), ^{

#if VERSION_MAJOR == 4 && VERSION_MINOR >= 6

		/*
		 * Godot 4.6 hosts the engine view controller inside
		 * a SwiftUI WindowGroup. Therefore we use the
		 * GDTAppDelegateService to obtain the current
		 * view controller.
		 */
		UIViewController *root_controller =
				[GDTAppDelegateService viewController];

#else

		UIViewController *root_controller =
				[[UIApplication sharedApplication]
						delegate].window.rootViewController;

#endif

		if (!root_controller) {
			NSLog(@"PhotoPicker: root view controller not found.");
			return;
		}

		/*
		 * Protection at the native-plugin level.
		 *
		 * Fluxus currently uses:
		 *   Free    -> 3
		 *   Premium -> 12
		 */
		NSInteger limit = selectionLimit;

		if (limit < 1) {
			limit = 1;
		}

		if (limit > MAX_SELECTION_LIMIT) {
			limit = MAX_SELECTION_LIMIT;
		}

		/*
		 * PHPicker is the iOS Photos picker.
		 */
		if (@available(iOS 14.0, *)) {

			PHPickerConfiguration *configuration =
					[[PHPickerConfiguration alloc]
							initWithPhotoLibrary:
									[PHPhotoLibrary
											sharedPhotoLibrary]];

			/*
			 * Only images are presented.
			 */
			configuration.filter =
					[PHPickerFilter imagesFilter];

			/*
			 * Maximum number of images.
			 */
			configuration.selectionLimit = limit;

			/*
			 * On iOS 15+, preserve the order in which
			 * the user selected the images.
			 */
			if (@available(iOS 15.0, *)) {
				configuration.selection =
						PHPickerConfigurationSelectionOrdered;
			}

			/*
			 * Prefer the current representation of the asset.
			 */
			configuration.preferredAssetRepresentationMode =
					PHPickerConfigurationAssetRepresentationModeCurrent;

			PHPickerViewController *picker =
					[[PHPickerViewController alloc]
							initWithConfiguration:
									configuration];

			picker.delegate = self;

			[root_controller
					presentViewController:
							picker
					animated:YES
					completion:nil];

		} else {

			NSLog(
					@"PhotoPicker: PHPicker requires iOS 14 or later.");
		}
	});
}


- (void)picker:(PHPickerViewController *)picker
		didFinishPicking:(NSArray<PHPickerResult *> *)results {

	/*
	 * The user cancelled the picker.
	 */
	if (results.count == 0) {

		[picker
				dismissViewControllerAnimated:YES
				completion:nil];

		Array images;

		PhotoPicker::get_singleton()
				->select_images(images);

		return;
	}

	/*
	 * Keep UIImage objects in Objective-C memory while the
	 * asynchronous NSItemProvider operations are running.
	 *
	 * The array is indexed according to the PHPicker result
	 * order so that the selection order can be preserved.
	 */
	NSMutableArray *orderedImages =
			[NSMutableArray arrayWithCapacity:
					results.count];

	for (NSInteger i = 0;
			i < results.count;
			i++) {

		[orderedImages
				addObject:
						[NSNull null]];
	}

	dispatch_group_t group =
			dispatch_group_create();

	for (NSInteger index = 0;
			index < results.count;
			index++) {

		PHPickerResult *result =
				results[index];

		NSItemProvider *provider =
				result.itemProvider;

		if (![provider
				canLoadObjectOfClass:
						[UIImage class]]) {

			continue;
		}

		dispatch_group_enter(group);

		[provider
				loadObjectOfClass:
						[UIImage class]
				completionHandler:
						^(UIImage *image,
								NSError *error) {

			if (error) {

				NSLog(
						@"PhotoPicker: error loading image: %@",
						error);
			}

			/*
			 * UIImage is retained in orderedImages.
			 *
			 * Mutating the NSMutableArray is performed
			 * on the main queue.
			 */
			dispatch_async(
					dispatch_get_main_queue(),
					^{

						if (image) {
							orderedImages[index] = image;
						}

						dispatch_group_leave(group);
					});
		}];
	}

	/*
	 * Once all asynchronous image loads have completed,
	 * convert the UIImages into Godot Image objects.
	 */
	dispatch_group_notify(
			group,
			dispatch_get_main_queue(),
			^{

				Array images;

				for (NSInteger i = 0;
						i < orderedImages.count;
						i++) {

					id object =
							orderedImages[i];

					if (object == [NSNull null]) {
						continue;
					}

					UIImage *image =
							(UIImage *)object;

					Ref<Image> godot_image =
							[self
									godotImageFromUIImage:
											image];

					if (godot_image.is_valid()) {
						images.push_back(godot_image);
					}
				}

				/*
				 * Close the PHPicker UI before returning
				 * the images to Godot.
				 */
				[picker
						dismissViewControllerAnimated:
								YES
						completion:^{
							PhotoPicker::get_singleton()
									->select_images(images);
						}];
			});
}


/*************************************************************************/
/* UIImage -> Godot Image                                                */
/*************************************************************************/

- (Ref<Image>)godotImageFromUIImage:(UIImage *)image {

	if (!image) {
		return Ref<Image>();
	}

	/*
	 * Renderiza o UIImage em um CGContext.
	 *
	 * O drawInRect: respeita a orientação do UIImage,
	 * incluindo a orientação proveniente de fotos HEIC/EXIF.
	 *
	 * NÃO fazemos CGContextTranslateCTM/ScaleCTM manualmente
	 * neste primeiro contexto.
	 */
	UIGraphicsBeginImageContextWithOptions(
			image.size,
			YES,
			1.0);

	CGContextRef context =
			UIGraphicsGetCurrentContext();

	if (!context) {

		UIGraphicsEndImageContext();

		return Ref<Image>();
	}

	[image
			drawInRect:
					CGRectMake(
							0,
							0,
							image.size.width,
							image.size.height)];

	CGImageRef cgImage =
			CGBitmapContextCreateImage(context);

	if (!cgImage) {

		UIGraphicsEndImageContext();

		return Ref<Image>();
	}

	size_t width =
			CGImageGetWidth(cgImage);

	size_t height =
			CGImageGetHeight(cgImage);

	size_t bytesPerPixel = 4;
	size_t bytesPerRow =
			width * bytesPerPixel;
	size_t bitsPerComponent = 8;

	CGColorSpaceRef colorSpace =
			CGColorSpaceCreateDeviceRGB();

	if (!colorSpace) {

		CGImageRelease(cgImage);
		UIGraphicsEndImageContext();

		return Ref<Image>();
	}

	CFMutableDataRef data =
			CFDataCreateMutable(
					kCFAllocatorDefault,
					width *
							height *
							bytesPerPixel);

	if (!data) {

		CGColorSpaceRelease(colorSpace);
		CGImageRelease(cgImage);
		UIGraphicsEndImageContext();

		return Ref<Image>();
	}

	CFDataSetLength(
			data,
			width *
					height *
					bytesPerPixel);

	CGContextRef bitmapContext =
			CGBitmapContextCreate(
					CFDataGetMutableBytePtr(data),
					width,
					height,
					bitsPerComponent,
					bytesPerRow,
					colorSpace,
					kCGImageAlphaPremultipliedLast |
							kCGBitmapByteOrderDefault);

	if (!bitmapContext) {

		CFRelease(data);
		CGColorSpaceRelease(colorSpace);
		CGImageRelease(cgImage);
		UIGraphicsEndImageContext();

		return Ref<Image>();
	}

	/*
	 * O CGImage possui origem inferior-esquerda,
	 * enquanto o bitmap entregue ao Godot deve
	 * manter a orientação visual normalizada.
	 */
	CGContextTranslateCTM(
			bitmapContext,
			0,
			static_cast<CGFloat>(height));

	CGContextScaleCTM(
			bitmapContext,
			1.0,
			-1.0);

	CGContextDrawImage(
			bitmapContext,
			CGRectMake(
					0,
					0,
					static_cast<CGFloat>(width),
					static_cast<CGFloat>(height)),
			cgImage);

	CGImageRef rgbaImage =
			CGBitmapContextCreateImage(
					bitmapContext);

	Ref<Image> result;

	if (rgbaImage) {

		CGDataProviderRef rgbaProvider =
				CGImageGetDataProvider(
						rgbaImage);

		CFDataRef rgbaData =
				CGDataProviderCopyData(
						rgbaProvider);

		if (rgbaData) {

			CFIndex length =
					CFDataGetLength(rgbaData);

			Vector<uint8_t> img_data;

			img_data.resize(length);

			memcpy(
					img_data.ptrw(),
					CFDataGetBytePtr(rgbaData),
					length);

			result.instantiate();

			result->set_data(
					width,
					height,
					false,
					Image::FORMAT_RGBA8,
					img_data);

			CFRelease(rgbaData);
		}

		CGImageRelease(rgbaImage);
	}

	CGContextRelease(bitmapContext);

	CFRelease(data);

	CGColorSpaceRelease(colorSpace);

	CGImageRelease(cgImage);

	UIGraphicsEndImageContext();

	return result;
}

@end


/*************************************************************************/
/* Singleton                                                             */
/*************************************************************************/

PhotoPicker *PhotoPicker::get_singleton() {
	return instance;
}


/*************************************************************************/
/* Godot bindings                                                        */
/*************************************************************************/

void PhotoPicker::_bind_methods() {

	ClassDB::bind_method(
			D_METHOD(
					"present_multiple",
					"selection_limit"),
			&PhotoPicker::present_multiple);

	ClassDB::bind_method(
			D_METHOD(
					"save_image",
					"path",
					"filename"),
			&PhotoPicker::save_image);

	ClassDB::bind_method(
			D_METHOD(
					"save_video",
					"path",
					"filename"),
			&PhotoPicker::save_video);

	ClassDB::bind_method(
			D_METHOD(
					"export_frames",
					"frames_directory",
					"output_path",
					"fps"),
			&PhotoPicker::export_frames);

	ADD_SIGNAL(
			MethodInfo(
					"images_picked",
					PropertyInfo(
							Variant::ARRAY,
							"images")));

	ADD_SIGNAL(
			MethodInfo(
					"image_saved",
					PropertyInfo(
							Variant::BOOL,
							"success"),
					PropertyInfo(
							Variant::STRING,
							"message")));

	ADD_SIGNAL(
			MethodInfo(
					"video_saved",
					PropertyInfo(
							Variant::BOOL,
							"success"),
					PropertyInfo(
							Variant::STRING,
							"message")));
}


/*************************************************************************/
/* Present multiple                                                       */
/*************************************************************************/

void PhotoPicker::present_multiple(
		int selection_limit) {

	[godot_photo_picker
			presentMultiple:
					selection_limit];
}


/*************************************************************************/
/* Select images                                                         */
/*************************************************************************/

void PhotoPicker::select_images(
		Array images) {

	emit_signal(
			"images_picked",
			images);
}


/*************************************************************************/
/* Save image                                                            */
/*************************************************************************/

void PhotoPicker::save_image(
		const String &path,
		const String &filename) {

	NSString *ns_path =
			[NSString
					stringWithUTF8String:
							path.utf8().get_data()];

	NSString *ns_filename =
			[NSString
					stringWithUTF8String:
							filename.utf8().get_data()];

	if (!ns_path ||
			!ns_filename) {

		emit_image_saved(
				false,
				String(
						"Invalid image path or filename."));

		return;
	}

	NSURL *file_url =
			[NSURL
					fileURLWithPath:
							ns_path];

	if (![[NSFileManager defaultManager]
			fileExistsAtPath:
					ns_path]) {

		NSString *error_message =
				[NSString
						stringWithFormat:
								@"Image file not found: %@",
								ns_filename];

		emit_image_saved(
				false,
				String::utf8(
						[error_message
								UTF8String]));

		return;
	}

	PHPhotoLibrary *photo_library =
			[PHPhotoLibrary
					sharedPhotoLibrary];

	PHAuthorizationStatus status =
			[PHPhotoLibrary
					authorizationStatusForAccessLevel:
							PHAccessLevelAddOnly];

	if (status ==
			PHAuthorizationStatusNotDetermined) {

		[PHPhotoLibrary
				requestAuthorizationForAccessLevel:
						PHAccessLevelAddOnly
				handler:
						^(PHAuthorizationStatus new_status) {

			dispatch_async(
					dispatch_get_main_queue(),
					^{

						if (new_status ==
								PHAuthorizationStatusAuthorized) {

							[photo_library
									performChanges:
											^{

								[PHAssetChangeRequest
										creationRequestForAssetFromImageAtFileURL:
												file_url];

							}
									completionHandler:
											^(BOOL success,
													NSError *error) {

								dispatch_async(
										dispatch_get_main_queue(),
										^{

									if (success) {

										PhotoPicker::get_singleton()
												->emit_image_saved(
														true,
														String(""));

									} else {

										NSString *message =
												error ?
														error.localizedDescription :
														@"Unknown Photos error.";

										PhotoPicker::get_singleton()
												->emit_image_saved(
														false,
														String::utf8(
																[message
																		UTF8String]));
									}
								});
							}];

						} else {

							PhotoPicker::get_singleton()
									->emit_image_saved(
											false,
											String(
													"Photo Library permission denied."));
						}
					});
		}];

		return;
	}

	if (status !=
			PHAuthorizationStatusAuthorized) {

		emit_image_saved(
				false,
				String(
						"Photo Library permission denied."));

		return;
	}

	[photo_library
			performChanges:
					^{

		[PHAssetChangeRequest
				creationRequestForAssetFromImageAtFileURL:
						file_url];

	}
			completionHandler:
					^(BOOL success,
							NSError *error) {

		dispatch_async(
				dispatch_get_main_queue(),
				^{

			if (success) {

				PhotoPicker::get_singleton()
						->emit_image_saved(
								true,
								String(""));

			} else {

				NSString *message =
						error ?
								error.localizedDescription :
								@"Unknown Photos error.";

				PhotoPicker::get_singleton()
						->emit_image_saved(
								false,
								String::utf8(
										[message
												UTF8String]));
			}
		});
	}];
}


/*************************************************************************/
/* Save video                                                            */
/*************************************************************************/

void PhotoPicker::save_video(
		const String &path,
		const String &filename) {

	NSString *ns_path =
			[NSString
					stringWithUTF8String:
							path.utf8().get_data()];

	NSString *ns_filename =
			[NSString
					stringWithUTF8String:
							filename.utf8().get_data()];

	if (!ns_path ||
			!ns_filename) {

		emit_video_saved(
				false,
				String(
						"Invalid video path or filename."));

		return;
	}

	NSURL *file_url =
			[NSURL
					fileURLWithPath:
							ns_path];

	if (![[NSFileManager defaultManager]
			fileExistsAtPath:
					ns_path]) {

		NSString *error_message =
				[NSString
						stringWithFormat:
								@"Video file not found: %@",
								ns_filename];

		emit_video_saved(
				false,
				String::utf8(
						[error_message
								UTF8String]));

		return;
	}

	PHPhotoLibrary *photo_library =
			[PHPhotoLibrary
					sharedPhotoLibrary];

	PHAuthorizationStatus status =
			[PHPhotoLibrary
					authorizationStatusForAccessLevel:
							PHAccessLevelAddOnly];

	if (status ==
			PHAuthorizationStatusNotDetermined) {

		[PHPhotoLibrary
				requestAuthorizationForAccessLevel:
						PHAccessLevelAddOnly
				handler:
						^(PHAuthorizationStatus new_status) {

			dispatch_async(
					dispatch_get_main_queue(),
					^{

						if (new_status ==
								PHAuthorizationStatusAuthorized) {

							[photo_library
									performChanges:
											^{

								[PHAssetChangeRequest
										creationRequestForAssetFromVideoAtFileURL:
												file_url];

							}
									completionHandler:
											^(BOOL success,
													NSError *error) {

								dispatch_async(
										dispatch_get_main_queue(),
										^{

									if (success) {

										PhotoPicker::get_singleton()
												->emit_video_saved(
														true,
														String(""));

									} else {

										NSString *message =
												error ?
														error.localizedDescription :
														@"Unknown Photos error.";

										PhotoPicker::get_singleton()
												->emit_video_saved(
														false,
														String::utf8(
																[message
																		UTF8String]));
									}
								});
							}];

						} else {

							PhotoPicker::get_singleton()
									->emit_video_saved(
											false,
											String(
													"Photo Library permission denied."));
						}
					});
		}];

		return;
	}

	if (status !=
			PHAuthorizationStatusAuthorized) {

		emit_video_saved(
				false,
				String(
						"Photo Library permission denied."));

		return;
	}

	[photo_library
			performChanges:
					^{

		[PHAssetChangeRequest
				creationRequestForAssetFromVideoAtFileURL:
						file_url];

	}
			completionHandler:
					^(BOOL success,
							NSError *error) {

		dispatch_async(
				dispatch_get_main_queue(),
				^{

			if (success) {

				PhotoPicker::get_singleton()
						->emit_video_saved(
								true,
								String(""));

			} else {

				NSString *message =
						error ?
								error.localizedDescription :
								@"Unknown Photos error.";

				PhotoPicker::get_singleton()
						->emit_video_saved(
								false,
								String::utf8(
										[message
												UTF8String]));
			}
		});
	}];
}


/*************************************************************************/
/* UIImage -> CVPixelBuffer                                               */
/*************************************************************************/

/*
 * Converte um CGImage em um CVPixelBuffer BGRA.
 *
 * O AVAssetWriterInputPixelBufferAdaptor receberá esses buffers
 * para codificação H.264.
 */
static CVPixelBufferRef create_pixel_buffer_from_image(
		CGImageRef image,
		size_t width,
		size_t height) {

	CVPixelBufferRef pixel_buffer = nullptr;

	NSDictionary *attributes = @{
		(id)kCVPixelBufferCGImageCompatibilityKey : @YES,
		(id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES
	};

	CVReturn result =
			CVPixelBufferCreate(
					kCFAllocatorDefault,
					width,
					height,
					kCVPixelFormatType_32BGRA,
					(__bridge CFDictionaryRef)
							attributes,
					&pixel_buffer);

	if (result != kCVReturnSuccess ||
			pixel_buffer == nullptr) {

		return nullptr;
	}

	CVPixelBufferLockBaseAddress(
			pixel_buffer,
			0);

	void *base_address =
			CVPixelBufferGetBaseAddress(
					pixel_buffer);

	size_t bytes_per_row =
			CVPixelBufferGetBytesPerRow(
					pixel_buffer);

	CGColorSpaceRef color_space =
			CGColorSpaceCreateDeviceRGB();

	CGContextRef context =
			CGBitmapContextCreate(
					base_address,
					width,
					height,
					8,
					bytes_per_row,
					color_space,
					kCGBitmapByteOrder32Little |
							kCGImageAlphaPremultipliedFirst);

	if (context == nullptr) {

		CGColorSpaceRelease(
				color_space);

		CVPixelBufferUnlockBaseAddress(
				pixel_buffer,
				0);

		CFRelease(pixel_buffer);

		return nullptr;
	}

	/*
	 * Corrige a orientação vertical do CoreGraphics.
	 */
	CGContextTranslateCTM(
			context,
			0,
			static_cast<CGFloat>(
					height));

	CGContextScaleCTM(
			context,
			1.0,
			-1.0);

	CGContextDrawImage(
			context,
			CGRectMake(
					0,
					0,
					static_cast<CGFloat>(
							width),
					static_cast<CGFloat>(
							height)),
			image);

	CGContextRelease(context);

	CGColorSpaceRelease(
			color_space);

	CVPixelBufferUnlockBaseAddress(
			pixel_buffer,
			0);

	return pixel_buffer;
}


/*************************************************************************/
/* Export frames -> MP4                                                  */
/*************************************************************************/

bool PhotoPicker::export_frames(
		const String &frames_directory,
		const String &output_path,
		int fps) {

	/*************************************************************************/
	/* Validate parameters                                                   */
	/*************************************************************************/

	if (frames_directory.length() == 0) {

		ERR_PRINT(
				"PhotoPicker: frames directory is empty.");

		return false;
	}

	if (output_path.length() == 0) {

		ERR_PRINT(
				"PhotoPicker: output path is empty.");

		return false;
	}

	if (fps <= 0) {

		ERR_PRINT(
				"PhotoPicker: invalid FPS.");

		return false;
	}


	/*************************************************************************/
	/* Convert Godot strings to NSString                                     */
	/*************************************************************************/

	NSString *frames_path =
			[NSString
					stringWithUTF8String:
							frames_directory
									.utf8()
									.get_data()];

	NSString *output_file =
			[NSString
					stringWithUTF8String:
							output_path
									.utf8()
									.get_data()];

	if (frames_path == nil ||
			output_file == nil) {

		ERR_PRINT(
				"PhotoPicker: invalid UTF-8 path.");

		return false;
	}


	/*************************************************************************/
	/* Validate frames directory                                             */
	/*************************************************************************/

	NSFileManager *file_manager =
			[NSFileManager defaultManager];

	BOOL is_directory = NO;

	BOOL exists =
			[file_manager
					fileExistsAtPath:
							frames_path
					isDirectory:
							&is_directory];

	if (!exists ||
			!is_directory) {

		ERR_PRINT(
				"PhotoPicker: frames directory does not exist.");

		return false;
	}


	/*************************************************************************/
	/* Read directory                                                        */
	/*************************************************************************/

	NSError *directory_error = nil;

	NSArray<NSString *> *all_files =
			[file_manager
					contentsOfDirectoryAtPath:
							frames_path
					error:
							&directory_error];

	if (all_files == nil) {

		if (directory_error != nil) {

			NSLog(
					@"PhotoPicker: directory error: %@",
					directory_error.localizedDescription);
		}

		ERR_PRINT(
				"PhotoPicker: unable to read frames directory.");

		return false;
	}


	/*************************************************************************/
	/* Select PNG frames                                                     */
	/*************************************************************************/

	NSArray<NSString *> *sorted_files =
			[all_files
					sortedArrayUsingComparator:
							^NSComparisonResult(
									NSString *a,
									NSString *b) {

								return [a
										compare:b
										options:
												NSNumericSearch];
							}];

	NSMutableArray<NSString *> *frame_files =
			[NSMutableArray array];


	for (NSString *file in sorted_files) {

		NSString *extension =
				[file.pathExtension
						lowercaseString];

		if ([extension
				isEqualToString:
						@"png"] &&
				[file
						hasPrefix:
								@"frame_"]) {

			[frame_files
					addObject:
							file];
		}
	}


	if (frame_files.count == 0) {

		ERR_PRINT(
				"PhotoPicker: no PNG frames found.");

		return false;
	}


	/*************************************************************************/
	/* Load first frame                                                      */
	/*************************************************************************/

	NSString *first_frame_path =
			[frames_path
					stringByAppendingPathComponent:
							frame_files[0]];

	UIImage *first_image =
			[UIImage
					imageWithContentsOfFile:
							first_frame_path];

	if (first_image == nil ||
			first_image.CGImage == nullptr) {

		ERR_PRINT(
				"PhotoPicker: unable to load first PNG frame.");

		return false;
	}

	CGImageRef first_cg_image =
			first_image.CGImage;

	size_t width =
			CGImageGetWidth(
					first_cg_image);

	size_t height =
			CGImageGetHeight(
					first_cg_image);

	if (width == 0 ||
			height == 0) {

		ERR_PRINT(
				"PhotoPicker: invalid frame dimensions.");

		return false;
	}


	/*************************************************************************/
	/* H.264 requires even dimensions                                        */
	/*************************************************************************/

	if ((width % 2) != 0 ||
			(height % 2) != 0) {

		ERR_PRINT(
				"PhotoPicker: frame dimensions must be even for H.264.");

		return false;
	}


	/*************************************************************************/
	/* Remove previous output file                                           */
	/*************************************************************************/

	if ([file_manager
			fileExistsAtPath:
					output_file]) {

		NSError *remove_error = nil;

		BOOL removed =
				[file_manager
						removeItemAtPath:
								output_file
						error:
								&remove_error];

		if (!removed) {

			if (remove_error != nil) {

				NSLog(
						@"PhotoPicker: unable to remove existing output: %@",
						remove_error.localizedDescription);
			}

			return false;
		}
	}


	/*************************************************************************/
	/* Create output directory                                               */
	/*************************************************************************/

	NSString *output_directory =
			[output_file
					stringByDeletingLastPathComponent];

	if (output_directory.length > 0) {

		NSError *directory_creation_error = nil;

		BOOL created =
				[file_manager
						createDirectoryAtPath:
								output_directory
						withIntermediateDirectories:YES
						attributes:nil
						error:
								&directory_creation_error];

		if (!created &&
				![file_manager
						fileExistsAtPath:
								output_directory]) {

			if (directory_creation_error != nil) {

				NSLog(
						@"PhotoPicker: unable to create output directory: %@",
						directory_creation_error.localizedDescription);
			}

			return false;
		}
	}


	/*************************************************************************/
	/* Create AVAssetWriter                                                  */
	/*************************************************************************/

	NSURL *output_url =
			[NSURL
					fileURLWithPath:
							output_file];

	NSError *writer_error = nil;

	AVAssetWriter *writer =
			[[AVAssetWriter alloc]
					initWithURL:
							output_url
					fileType:
							AVFileTypeMPEG4
					error:
							&writer_error];

	if (writer == nil) {

		if (writer_error != nil) {

			NSLog(
					@"PhotoPicker: AVAssetWriter error: %@",
					writer_error.localizedDescription);
		}

		ERR_PRINT(
				"PhotoPicker: unable to create AVAssetWriter.");

		return false;
	}


	/*************************************************************************/
	/* H.264 settings                                                        */
	/*************************************************************************/

	NSDictionary *compression_properties = @{
		AVVideoAverageBitRateKey :
				@(8000000),

		AVVideoProfileLevelKey :
				AVVideoProfileLevelH264HighAutoLevel
	};

	NSDictionary *video_settings = @{
		AVVideoCodecKey :
				AVVideoCodecTypeH264,

		AVVideoWidthKey :
				@(width),

		AVVideoHeightKey :
				@(height),

		AVVideoCompressionPropertiesKey :
				compression_properties
	};


	/*************************************************************************/
	/* Create video input                                                    */
	/*************************************************************************/

	AVAssetWriterInput *video_input =
			[[AVAssetWriterInput alloc]
					initWithMediaType:
							AVMediaTypeVideo
					outputSettings:
							video_settings];

	video_input.expectsMediaDataInRealTime = NO;

	if (![writer
			canAddInput:
					video_input]) {

		ERR_PRINT(
				"PhotoPicker: cannot add video input.");

		return false;
	}

	[writer
			addInput:
					video_input];


	/*************************************************************************/
	/* Create pixel buffer adaptor                                           */
	/*************************************************************************/

	NSDictionary *source_pixel_buffer_attributes = @{
		(NSString *)kCVPixelBufferPixelFormatTypeKey :
				@(kCVPixelFormatType_32BGRA),

		(NSString *)kCVPixelBufferWidthKey :
				@(width),

		(NSString *)kCVPixelBufferHeightKey :
				@(height)
	};

	AVAssetWriterInputPixelBufferAdaptor *pixel_buffer_adaptor =
			[[AVAssetWriterInputPixelBufferAdaptor alloc]
					initWithAssetWriterInput:
							video_input
					sourcePixelBufferAttributes:
							source_pixel_buffer_attributes];

	if (pixel_buffer_adaptor == nil) {

		ERR_PRINT(
				"PhotoPicker: unable to create pixel buffer adaptor.");

		return false;
	}


	/*************************************************************************/
	/* Start writing                                                         */
	/*************************************************************************/

	if (![writer
			startWriting]) {

		NSError *error =
				writer.error;

		if (error != nil) {

			NSLog(
					@"PhotoPicker: startWriting error: %@",
					error.localizedDescription);
		}

		ERR_PRINT(
				"PhotoPicker: unable to start writing.");

		return false;
	}

	[writer
			startSessionAtSourceTime:
					kCMTimeZero];


	/*************************************************************************/
	/* Append frames                                                         */
	/*************************************************************************/

	for (NSUInteger index = 0;
			index < frame_files.count;
			index++) {

		/*
		 * Aguarda espaço no AVAssetWriterInput.
		 *
		 * A implementação é síncrona.
		 */
		while (!video_input.readyForMoreMediaData) {

			[NSThread
					sleepForTimeInterval:
							0.001];

			if (writer.status ==
						AVAssetWriterStatusFailed ||
					writer.status ==
						AVAssetWriterStatusCancelled) {

				break;
			}
		}

		if (writer.status ==
					AVAssetWriterStatusFailed ||
				writer.status ==
					AVAssetWriterStatusCancelled) {

			break;
		}


		/*************************************************************************/
		/* Load PNG                                                              */
		/*************************************************************************/

		NSString *frame_path =
				[frames_path
						stringByAppendingPathComponent:
								frame_files[index]];

		UIImage *image =
				[UIImage
						imageWithContentsOfFile:
								frame_path];

		if (image == nil ||
				image.CGImage == nullptr) {

			NSLog(
					@"PhotoPicker: unable to load frame: %@",
					frame_files[index]);

			[video_input
					markAsFinished];

			[writer
					cancelWriting];

			return false;
		}

		CGImageRef image_ref =
				image.CGImage;

		size_t image_width =
				CGImageGetWidth(
						image_ref);

		size_t image_height =
				CGImageGetHeight(
						image_ref);


		/*************************************************************************/
		/* Validate frame dimensions                                             */
		/*************************************************************************/

		if (image_width != width ||
				image_height != height) {

			NSLog(
					@"PhotoPicker: frame size mismatch: %@",
					frame_files[index]);

			[video_input
					markAsFinished];

			[writer
					cancelWriting];

			return false;
		}


		/*************************************************************************/
		/* Create pixel buffer                                                   */
		/*************************************************************************/

		CVPixelBufferRef pixel_buffer =
				create_pixel_buffer_from_image(
						image_ref,
						width,
						height);

		if (pixel_buffer == nullptr) {

			ERR_PRINT(
					"PhotoPicker: unable to create pixel buffer.");

			[video_input
					markAsFinished];

			[writer
					cancelWriting];

			return false;
		}


		/*************************************************************************/
		/* Presentation timestamp                                                */
		/*************************************************************************/

		CMTime presentation_time =
				CMTimeMake(
						static_cast<int64_t>(
								index),
						static_cast<int32_t>(
								fps));


		/*************************************************************************/
		/* Append pixel buffer                                                   */
		/*************************************************************************/

		BOOL appended =
				[pixel_buffer_adaptor
						appendPixelBuffer:
								pixel_buffer
						withPresentationTime:
								presentation_time];

		CVPixelBufferRelease(
				pixel_buffer);

		if (!appended) {

			NSError *error =
					writer.error;

			if (error != nil) {

				NSLog(
						@"PhotoPicker: append error: %@",
						error.localizedDescription);
			}

			[video_input
					markAsFinished];

			[writer
					cancelWriting];

			return false;
		}
	}


	/*************************************************************************/
	/* Verify writer status                                                  */
	/*************************************************************************/

	if (writer.status !=
			AVAssetWriterStatusWriting) {

		NSError *error =
				writer.error;

		if (error != nil) {

			NSLog(
					@"PhotoPicker: writer stopped: %@",
					error.localizedDescription);
		}

		return false;
	}


	/*************************************************************************/
	/* Finish video                                                          */
	/*************************************************************************/

	[video_input
			markAsFinished];

	dispatch_semaphore_t semaphore =
			dispatch_semaphore_create(0);

	__block BOOL finish_success =
			NO;

	[writer
			finishWritingWithCompletionHandler:
					^{

		finish_success =
				(writer.status ==
						AVAssetWriterStatusCompleted);

		dispatch_semaphore_signal(
				semaphore);
	}];


	dispatch_semaphore_wait(
			semaphore,
			DISPATCH_TIME_FOREVER);


	/*************************************************************************/
	/* Verify final result                                                   */
	/*************************************************************************/

	if (!finish_success) {

		NSError *error =
				writer.error;

		if (error != nil) {

			NSLog(
					@"PhotoPicker: finishWriting error: %@",
					error.localizedDescription);
		}

		ERR_PRINT(
				"PhotoPicker: failed to finish MP4.");

		return false;
	}

	if (![file_manager
			fileExistsAtPath:
					output_file]) {

		ERR_PRINT(
				"PhotoPicker: MP4 was not created.");

		return false;
	}

	NSDictionary *attributes =
			[file_manager
					attributesOfItemAtPath:
							output_file
					error:
							nil];

	unsigned long long file_size =
			[attributes fileSize];

	if (file_size == 0) {

		ERR_PRINT(
				"PhotoPicker: generated MP4 is empty.");

		return false;
	}

	NSLog(
			@"PhotoPicker: MP4 created successfully: %@ (%llu bytes)",
			output_file,
			file_size);

	return true;
}


/*************************************************************************/
/* Signals                                                               */
/*************************************************************************/

void PhotoPicker::emit_image_saved(
		bool success,
		const String &message) {

	emit_signal(
			"image_saved",
			success,
			message);
}


void PhotoPicker::emit_video_saved(
		bool success,
		const String &message) {

	emit_signal(
			"video_saved",
			success,
			message);
}


/*************************************************************************/
/* Constructor                                                           */
/*************************************************************************/

PhotoPicker::PhotoPicker() {

	instance = this;

	godot_photo_picker =
			[[GodotPhotoPicker alloc]
					init];
}


/*************************************************************************/
/* Destructor                                                            */
/*************************************************************************/

PhotoPicker::~PhotoPicker() {

	instance = NULL;

	godot_photo_picker = nil;
}
