/*************************************************************************/
/*  photo_saver.mm                                                      */
/*************************************************************************/

#include "photo_saver.h"

#include "core/object/class_db.h"

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>


PhotoSaver *instance = NULL;


/*************************************************************************/
/*  Native Photo Saver                                                  */
/*************************************************************************/

@interface GodotPhotoSaver : NSObject

- (void)saveMediaAtPath:(NSString *)path
			   filename:(NSString *)filename;

@end


@implementation GodotPhotoSaver


/*************************************************************************/
/*  Save Image or Video to Photos                                       */
/*************************************************************************/

- (void)saveMediaAtPath:(NSString *)path
			   filename:(NSString *)filename {

	if (!path || path.length == 0) {
		NSLog(@"[PhotoSaver] ERROR: Empty file path.");
		return;
	}

	NSFileManager *file_manager =
			[NSFileManager defaultManager];

	if (![file_manager fileExistsAtPath:path]) {
		NSLog(@"[PhotoSaver] ERROR: File does not exist: %@", path);
		return;
	}

	NSURL *file_url =
			[NSURL fileURLWithPath:path];

	if (!file_url) {
		NSLog(@"[PhotoSaver] ERROR: Could not create file URL.");
		return;
	}


	/*********************************************************************/
	/*  Detect media type                                                */
	/*********************************************************************/

	NSString *extension =
			[[path pathExtension] lowercaseString];

	BOOL is_image =
			[extension isEqualToString:@"png"] ||
			[extension isEqualToString:@"jpg"] ||
			[extension isEqualToString:@"jpeg"] ||
			[extension isEqualToString:@"heic"] ||
			[extension isEqualToString:@"heif"];

	BOOL is_video =
			[extension isEqualToString:@"mp4"] ||
			[extension isEqualToString:@"mov"] ||
			[extension isEqualToString:@"m4v"];


	if (!is_image && !is_video) {

		NSLog(
			@"[PhotoSaver] ERROR: Unsupported media type: %@",
			extension
		);

		return;
	}


	/*********************************************************************/
	/*  Request Photo Library authorization                               */
	/*********************************************************************/

	PHAuthorizationStatus status =
			[PHPhotoLibrary authorizationStatus];


	if (status == PHAuthorizationStatusNotDetermined) {

		NSLog(
			@"[PhotoSaver] Requesting Photo Library authorization."
		);


		[PHPhotoLibrary requestAuthorization:
			^(PHAuthorizationStatus new_status) {

				if (new_status == PHAuthorizationStatusAuthorized) {

					dispatch_async(
						dispatch_get_main_queue(),
						^{
							[self saveMediaAtPath:path
										 filename:filename];
						}
					);

				} else {

					NSLog(
						@"[PhotoSaver] Photo Library authorization denied."
					);
				}
			}
		];

		return;
	}


	if (status != PHAuthorizationStatusAuthorized) {

		NSLog(
			@"[PhotoSaver] ERROR: Photo Library access not authorized."
		);

		return;
	}


	/*********************************************************************/
	/*  Save media                                                       */
	/*********************************************************************/

	NSLog(
		@"[PhotoSaver] Saving %@: %@",
		is_image ? @"image" : @"video",
		filename
	);


	PHPhotoLibrary *photo_library =
			[PHPhotoLibrary sharedPhotoLibrary];


	[photo_library
		performChanges:
			^{

				if (is_image) {

					/*****************************************************************/
					/*  Image                                                         */
					/*****************************************************************/

					[PHAssetChangeRequest
						creationRequestForAssetFromImageAtFileURL:file_url];

				} else {

					/*****************************************************************/
					/*  Video                                                         */
					/*****************************************************************/

					[PHAssetChangeRequest
						creationRequestForAssetFromVideoAtFileURL:file_url];
				}

			}
		completionHandler:
			^(BOOL success, NSError *error) {

				if (success) {

					NSLog(
						@"[PhotoSaver] Successfully saved %@: %@",
						is_image ? @"image" : @"video",
						filename
					);

				} else {

					NSLog(
						@"[PhotoSaver] ERROR saving %@: %@",
						is_image ? @"image" : @"video",
						error
					);
				}
			}
	];
}

@end


/*************************************************************************/
/*  Godot PhotoSaver                                                    */
/*************************************************************************/

PhotoSaver *PhotoSaver::get_singleton() {
	return instance;
}


/*************************************************************************/
/*  Godot bindings                                                      */
/*************************************************************************/

void PhotoSaver::_bind_methods() {

	ClassDB::bind_method(
		D_METHOD("save_image", "path", "filename"),
		&PhotoSaver::save_image
	);
}


/*************************************************************************/
/*  Save media                                                          */
/*************************************************************************/

void PhotoSaver::save_image(
		const String &path,
		const String &filename) {

	NSString *ns_path =
			[NSString stringWithUTF8String:
				path.utf8().get_data()];

	NSString *ns_filename =
			[NSString stringWithUTF8String:
				filename.utf8().get_data()];


	if (!ns_path) {
		NSLog(@"[PhotoSaver] ERROR: Invalid path.");
		return;
	}


	if (!ns_filename || ns_filename.length == 0) {
		ns_filename = @"Fluxus";
	}


	[godot_photo_saver
		saveMediaAtPath:ns_path
		filename:ns_filename];
}


/*************************************************************************/
/*  Constructor                                                         */
/*************************************************************************/

PhotoSaver::PhotoSaver() {

	instance = this;

	godot_photo_saver =
			[[GodotPhotoSaver alloc] init];
}


/*************************************************************************/
/*  Destructor                                                          */
/*************************************************************************/

PhotoSaver::~PhotoSaver() {

	instance = NULL;

	godot_photo_saver = nil;
}
