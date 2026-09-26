/*************************************************************************/
/*  photo_saver.mm                                                       */
/*************************************************************************/

#include "photo_saver.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

#if VERSION_MAJOR == 4
#if VERSION_MINOR >= 6
#import "drivers/apple_embedded/app_delegate_service.h"
#else
#import "drivers/apple_embedded/godot_app_delegate.h"
#endif
#endif


PhotoSaver *instance = NULL;


/*************************************************************************/
/*  Native Photo Saver                                                  */
/*************************************************************************/

@interface GodotPhotoSaver : NSObject
- (void)saveImageAtPath:(NSString *)path
			   filename:(NSString *)filename;
@end


@implementation GodotPhotoSaver


- (void)saveImageAtPath:(NSString *)path
			   filename:(NSString *)filename {

	dispatch_async(dispatch_get_main_queue(), ^{

		NSURL *fileURL =
				[NSURL fileURLWithPath:path];

		if (![[NSFileManager defaultManager]
				fileExistsAtPath:path]) {

			NSLog(
				@"PhotoSaver: file does not exist: %@",
				path
			);

			PhotoSaver::get_singleton()->emit_signal(
				"image_saved",
				false,
				@"Arquivo temporário não encontrado."
			);

			return;
		}


		/*****************************************************************/
		/* Request permission to add photos                              */
		/*****************************************************************/

		if (@available(iOS 14.0, *)) {

			PHAuthorizationStatus status =
					[PHPhotoLibrary
						authorizationStatusForAccessLevel:
							PHAccessLevelAddOnly];

			if (status == PHAuthorizationStatusDenied ||
				status == PHAuthorizationStatusRestricted) {

				NSLog(
					@"PhotoSaver: photo library access denied."
				);

				PhotoSaver::get_singleton()->emit_signal(
					"image_saved",
					false,
					@"Permissão para salvar no Fotos foi negada."
				);

				return;
			}


			if (status == PHAuthorizationStatusNotDetermined) {

				[[PHPhotoLibrary sharedPhotoLibrary]
					requestAuthorizationForAccessLevel:
						PHAccessLevelAddOnly
					handler:^(PHAuthorizationStatus newStatus) {

						dispatch_async(
							dispatch_get_main_queue(),
							^{

								if (newStatus ==
									PHAuthorizationStatusAuthorized ||
									newStatus ==
									PHAuthorizationStatusLimited) {

									[self
										saveImageFileURL:fileURL];
								}
								else {

									PhotoSaver::get_singleton()
										->emit_signal(
											"image_saved",
											false,
											@"Permissão para salvar no Fotos foi negada."
										);
								}
							}
						);
					}];

				return;
			}
		}


		/*****************************************************************/
		/* Already authorized                                            */
		/*****************************************************************/

		[self saveImageFileURL:fileURL];
	});
}


/*************************************************************************/
/*  Save image file into Photos                                         */
/*************************************************************************/

- (void)saveImageFileURL:(NSURL *)fileURL {

	if (!fileURL) {

		PhotoSaver::get_singleton()->emit_signal(
			"image_saved",
			false,
			@"URL da imagem inválida."
		);

		return;
	}


	[[PHPhotoLibrary sharedPhotoLibrary]
		performChanges:^{

			PHAssetChangeRequest *request =
				[PHAssetChangeRequest
					creationRequestForAssetFromImageAtFileURL:fileURL];

			if (!request) {

				NSLog(
					@"PhotoSaver: could not create asset request."
				);

				return;
			}

		}
		completionHandler:^(BOOL success, NSError *error) {

			dispatch_async(
				dispatch_get_main_queue(),
				^{

					if (success) {

						NSLog(
							@"PhotoSaver: image saved successfully."
						);

						PhotoSaver::get_singleton()
							->emit_signal(
								"image_saved",
								true,
								@""
							);

					}
					else {

						NSString *message;

						if (error) {
							message = [error localizedDescription];
						}
						else {
							message =
								@"Não foi possível salvar a imagem no Fotos.";
						}

						NSLog(
							@"PhotoSaver: error: %@",
							message
						);

						PhotoSaver::get_singleton()
							->emit_signal(
								"image_saved",
								false,
								String(
									[message UTF8String]
								)
							);
					}
				}
			);
		}];
}

@end


/*************************************************************************/
/*  Godot bindings                                                      */
/*************************************************************************/

void PhotoSaver::_bind_methods() {

	ClassDB::bind_method(
		D_METHOD(
			"save_image",
			"path",
			"filename"
		),
		&PhotoSaver::save_image
	);


	ADD_SIGNAL(
		MethodInfo(
			"image_saved",
			PropertyInfo(
				Variant::BOOL,
				"success"
			),
			PropertyInfo(
				Variant::STRING,
				"message"
			)
		)
	);
}


/*************************************************************************/
/*  Public API                                                           */
/*************************************************************************/

void PhotoSaver::save_image(
		String path,
		String filename) {

	[godot_photo_saver
		saveImageAtPath:
			[NSString
				stringWithUTF8String:
					path.utf8().get_data()]
		filename:
			[NSString
				stringWithUTF8String:
					filename.utf8().get_data()]
	];
}


/*************************************************************************/
/*  Singleton                                                             */
/*************************************************************************/

PhotoSaver *PhotoSaver::get_singleton() {
	return instance;
}


PhotoSaver::PhotoSaver() {

	instance = this;

	godot_photo_saver =
		[[GodotPhotoSaver alloc] init];
}


PhotoSaver::~PhotoSaver() {

	instance = NULL;

	godot_photo_saver = nil;
}


/*************************************************************************/
/*  Plugin initialization                                               */
/*************************************************************************/

extern "C" void godot_photosaver_init() {

	Engine::get_singleton()->add_singleton(
		Engine::Singleton(
			"PhotoSaver",
			memnew(PhotoSaver)
		)
	);
}


extern "C" void godot_photosaver_deinit() {

	if (PhotoSaver::get_singleton()) {

		memdelete(
			PhotoSaver::get_singleton()
		);
	}
}
