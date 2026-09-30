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
#include "core/string/ustring.h"
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
	 */
	void present_multiple(int selection_limit);

	/*
	 * Recebe as imagens selecionadas pelo PHPicker e
	 * emite o sinal "images_picked".
	 */
	void select_images(Array images);

	/*
	 * Salva uma imagem no Fotos do iOS.
	 */
	void save_image(
			const String &path,
			const String &filename);

	/*
	 * Salva um vídeo no Fotos do iOS.
	 */
	void save_video(
			const String &path,
			const String &filename);

	/*
	 * Emite o resultado da operação de salvamento da imagem.
	 *
	 * success = true  -> imagem salva com sucesso
	 * success = false -> falha
	 *
	 * message contém uma mensagem técnica para diagnóstico.
	 */
	void emit_image_saved(
			bool success,
			const String &message);

	/*
	 * Emite o resultado da operação de salvamento do vídeo.
	 */
	void emit_video_saved(
			bool success,
			const String &message);

	PhotoPicker();
	~PhotoPicker();

	static PhotoPicker *get_singleton();
};

#endif
