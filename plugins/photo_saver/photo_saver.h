/*************************************************************************/
/*  photo_saver.h                                                       */
/*************************************************************************/

#ifndef PHOTO_SAVER_H
#define PHOTO_SAVER_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/object.h"
#include "core/string/ustring.h"
#else
#include "core/object.h"
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
	void save_image(const String &path, const String &filename);

	PhotoSaver();
	~PhotoSaver();

	static PhotoSaver *get_singleton();
};

#endif
