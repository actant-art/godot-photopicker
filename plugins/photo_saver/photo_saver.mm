/*************************************************************************/
/*  photo_saver.mm                                                       */
/*************************************************************************/

#include "photo_saver.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/string/ustring.h"

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>


PhotoSaver *instance = nullptr;


/*************************************************************************/
/*  Native Photo Saver                                                   */
/*************************************************************************/

@interface GodotPhotoSaver : NSObject

- (void)saveImageAtPath:(NSString *)path
               filename:(NSString *)filename;

- (void)saveImageFileURL:(NSURL *)fileURL;

- (void)saveVideoAtPath:(NSString *)path
               filename:(NSString *)filename;

- (void)saveVideoFileURL:(NSURL *)fileURL;

@end


@implementation GodotPhotoSaver


/*************************************************************************/
/*  Save image at path                                                   */
/*************************************************************************/

- (void)saveImageAtPath:(NSString *)path
               filename:(NSString *)filename {

    (void)filename;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*****************************************************************/
            /* Check file                                                     */
            /*****************************************************************/

            if (![[NSFileManager defaultManager]
                    fileExistsAtPath:path]) {

                NSLog(
                    @"PhotoSaver: image file does not exist: %@",
                    path
                );

                PhotoSaver::get_singleton()->emit_signal(
                    "image_saved",
                    false,
                    "Arquivo temporário não encontrado."
                );

                return;
            }


            NSURL *fileURL =
                [NSURL fileURLWithPath:path];


            /*****************************************************************/
            /* Request Photos permission                                     */
            /*****************************************************************/

            PHAuthorizationStatus status =
                [PHPhotoLibrary authorizationStatus];


            if (status == PHAuthorizationStatusDenied ||
                status == PHAuthorizationStatusRestricted) {

                NSLog(
                    @"PhotoSaver: photo library access denied."
                );

                PhotoSaver::get_singleton()->emit_signal(
                    "image_saved",
                    false,
                    "Permissão para salvar no Fotos foi negada."
                );

                return;
            }


            if (status == PHAuthorizationStatusNotDetermined) {

                [PHPhotoLibrary
                    requestAuthorization:
                        ^(PHAuthorizationStatus newStatus) {

                            dispatch_async(
                                dispatch_get_main_queue(),
                                ^{

                                    if (
                                        newStatus ==
                                            PHAuthorizationStatusAuthorized ||
                                        newStatus ==
                                            PHAuthorizationStatusLimited
                                    ) {

                                        [self
                                            saveImageFileURL:
                                                fileURL];

                                    }
                                    else {

                                        PhotoSaver::get_singleton()
                                            ->emit_signal(
                                                "image_saved",
                                                false,
                                                "Permissão para salvar no Fotos foi negada."
                                            );
                                    }
                                }
                            );
                        }
                ];

                return;
            }


            /*****************************************************************/
            /* Already authorized                                             */
            /*****************************************************************/

            [self saveImageFileURL:fileURL];
        }
    );
}


/*************************************************************************/
/*  Save image file into Photos                                          */
/*************************************************************************/

- (void)saveImageFileURL:(NSURL *)fileURL {

    if (!fileURL) {

        PhotoSaver::get_singleton()->emit_signal(
            "image_saved",
            false,
            "URL da imagem inválida."
        );

        return;
    }


    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:
            ^{

                [PHAssetChangeRequest
                    creationRequestForAssetFromImageAtFileURL:
                        fileURL];

            }
        completionHandler:
            ^(BOOL success, NSError *error) {

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
                                    ""
                                );

                        }
                        else {

                            NSString *message;

                            if (error) {

                                message =
                                    [error localizedDescription];

                            }
                            else {

                                message =
                                    @"Não foi possível salvar a imagem no Fotos.";

                            }


                            NSLog(
                                @"PhotoSaver: image error: %@",
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
            }
    ];
}


/*************************************************************************/
/*  Save video at path                                                   */
/*************************************************************************/

- (void)saveVideoAtPath:(NSString *)path
               filename:(NSString *)filename {

    (void)filename;

    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            /*****************************************************************/
            /* Check file                                                     */
            /*****************************************************************/

            if (![[NSFileManager defaultManager]
                    fileExistsAtPath:path]) {

                NSLog(
                    @"PhotoSaver: video file does not exist: %@",
                    path
                );

                PhotoSaver::get_singleton()->emit_signal(
                    "video_saved",
                    false,
                    "Arquivo temporário do vídeo não encontrado."
                );

                return;
            }


            NSURL *fileURL =
                [NSURL fileURLWithPath:path];


            /*****************************************************************/
            /* Request Photos permission                                     */
            /*****************************************************************/

            PHAuthorizationStatus status =
                [PHPhotoLibrary authorizationStatus];


            if (status == PHAuthorizationStatusDenied ||
                status == PHAuthorizationStatusRestricted) {

                NSLog(
                    @"PhotoSaver: photo library access denied for video."
                );

                PhotoSaver::get_singleton()->emit_signal(
                    "video_saved",
                    false,
                    "Permissão para salvar no Fotos foi negada."
                );

                return;
            }


            if (status == PHAuthorizationStatusNotDetermined) {

                [PHPhotoLibrary
                    requestAuthorization:
                        ^(PHAuthorizationStatus newStatus) {

                            dispatch_async(
                                dispatch_get_main_queue(),
                                ^{

                                    if (
                                        newStatus ==
                                            PHAuthorizationStatusAuthorized ||
                                        newStatus ==
                                            PHAuthorizationStatusLimited
                                    ) {

                                        [self
                                            saveVideoFileURL:
                                                fileURL];

                                    }
                                    else {

                                        PhotoSaver::get_singleton()
                                            ->emit_signal(
                                                "video_saved",
                                                false,
                                                "Permissão para salvar no Fotos foi negada."
                                            );
                                    }
                                }
                            );
                        }
                ];

                return;
            }


            /*****************************************************************/
            /* Already authorized                                             */
            /*****************************************************************/

            [self saveVideoFileURL:fileURL];
        }
    );
}


/*************************************************************************/
/*  Save video file into Photos                                          */
/*************************************************************************/

- (void)saveVideoFileURL:(NSURL *)fileURL {

    if (!fileURL) {

        PhotoSaver::get_singleton()->emit_signal(
            "video_saved",
            false,
            "URL do vídeo inválida."
        );

        return;
    }


    [[PHPhotoLibrary sharedPhotoLibrary]
        performChanges:
            ^{

                [PHAssetChangeRequest
                    creationRequestForAssetFromVideoAtFileURL:
                        fileURL];

            }
        completionHandler:
            ^(BOOL success, NSError *error) {

                dispatch_async(
                    dispatch_get_main_queue(),
                    ^{

                        if (success) {

                            NSLog(
                                @"PhotoSaver: video saved successfully."
                            );

                            PhotoSaver::get_singleton()
                                ->emit_signal(
                                    "video_saved",
                                    true,
                                    ""
                                );

                        }
                        else {

                            NSString *message;

                            if (error) {

                                message =
                                    [error localizedDescription];

                            }
                            else {

                                message =
                                    @"Não foi possível salvar o vídeo no Fotos.";

                            }


                            NSLog(
                                @"PhotoSaver: video error: %@",
                                message
                            );


                            PhotoSaver::get_singleton()
                                ->emit_signal(
                                    "video_saved",
                                    false,
                                    String(
                                        [message UTF8String]
                                    )
                                );
                        }
                    }
                );
            }
    ];
}

@end


/*************************************************************************/
/*  Godot C API                                                          */
/*************************************************************************/

extern "C" void godot_photosaver_init();
extern "C" void godot_photosaver_deinit();


/*************************************************************************/
/*  Godot bindings                                                       */
/*************************************************************************/

void PhotoSaver::_bind_methods() {

    /*********************************************************************/
    /* Save image                                                        */
    /*********************************************************************/

    ClassDB::bind_method(
        D_METHOD(
            "save_image",
            "path",
            "filename"
        ),
        &PhotoSaver::save_image
    );


    /*********************************************************************/
    /* Save video                                                        */
    /*********************************************************************/

    ClassDB::bind_method(
        D_METHOD(
            "save_video",
            "path",
            "filename"
        ),
        &PhotoSaver::save_video
    );


    /*********************************************************************/
    /* Image saved signal                                                */
    /*********************************************************************/

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


    /*********************************************************************/
    /* Video saved signal                                                */
    /*********************************************************************/

    ADD_SIGNAL(
        MethodInfo(
            "video_saved",
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
/*  Public API                                                          */
/*************************************************************************/

void PhotoSaver::save_image(
    String path,
    String filename) {

    NSString *ns_path =
        [NSString
            stringWithUTF8String:
                path.utf8().get_data()];


    NSString *ns_filename =
        [NSString
            stringWithUTF8String:
                filename.utf8().get_data()];


    [godot_photo_saver
        saveImageAtPath:
            ns_path
        filename:
            ns_filename];
}


void PhotoSaver::save_video(
    String path,
    String filename) {

    NSString *ns_path =
        [NSString
            stringWithUTF8String:
                path.utf8().get_data()];


    NSString *ns_filename =
        [NSString
            stringWithUTF8String:
                filename.utf8().get_data()];


    [godot_photo_saver
        saveVideoAtPath:
            ns_path
        filename:
            ns_filename];
}


/*************************************************************************/
/*  Singleton                                                            */
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

    instance = nullptr;

    godot_photo_saver = nil;
}


/*************************************************************************/
/*  Plugin initialization                                               */
/*************************************************************************/

extern "C" {

void godot_photosaver_init() {

    Engine::get_singleton()->add_singleton(
        Engine::Singleton(
            "PhotoSaver",
            memnew(PhotoSaver)
        )
    );
}

void godot_photosaver_deinit() {

    if (PhotoSaver::get_singleton()) {

        memdelete(
            PhotoSaver::get_singleton()
        );
    }
}

}
