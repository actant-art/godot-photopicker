/*************************************************************************/
/*  photo_saver.h                                                       */
/*************************************************************************/

#ifndef PHOTO_SAVER_H
#define PHOTO_SAVER_H

#include "photo_saver.h"
#include "core/config/engine.h"

#import <Photos/Photos.h>

#if VERSION_MAJOR == 4
#include "core/io/image.h"
#include "core/object/object.h"
#include "core/variant/array.h"
#else
#include "core/image.h"
#include "core/object.h"
#include "core/variant/array.h"
#endif

#ifdef __OBJC__
@class GodotPhotoSaver;
#else
typedef void GodotPhotoSaver;
#endif

class PhotoSaver : public Object {
	GDCLASS(PhotoSaver, Object);

	static void _bind_methods();

	GodotPhotoSaver *godot_photo_saver;

public:
	void save_image(String path, String filename);

	PhotoSaver();
	~PhotoSaver();

	static PhotoSaver *get_singleton();
};

#endif
