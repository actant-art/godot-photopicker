/*************************************************************************/
/*  photo_picker.h                                                       */
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

#ifndef PHOTO_PICKER_H
#define PHOTO_PICKER_H

#include "core/version.h"

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
@class GodotPhotoPicker;
#else
typedef void GodotPhotoPicker;
#endif

class PhotoPicker : public Object {
	GDCLASS(PhotoPicker, Object);

	static void _bind_methods();

	GodotPhotoPicker *godot_photo_picker;

public:
	/*
	 * Abre o seletor de fotos do iOS usando PHPickerViewController.
	 *
	 * selection_limit:
	 *   1  = uma imagem
	 *   3  = limite do Fluxus Free
	 *   12 = limite do Fluxus Premium
	 *
	 * O limite também é protegido no código nativo.
	 */
	void present_multiple(int selection_limit);

	/*
	 * Recebe as imagens selecionadas pelo PHPicker e emite
	 * o sinal "images_picked".
	 */
	void select_images(Array images);

	PhotoPicker();

	~PhotoPicker();

	static PhotoPicker *get_singleton();
};

#endif
