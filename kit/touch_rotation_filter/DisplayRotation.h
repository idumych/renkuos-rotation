/*
 * Copyright 2026, Haiku, Inc. All rights reserved.
 * Distributed under the terms of the MIT License.
 *
 * Personal patch: software display rotation.
 *
 * Settings file: ~/config/settings/display_rotation
 *
 *	display right_side_up	# see below
 *	touch right_side_up		# optional, defaults to the display value
 *
 * Values:
 *	normal, right (90), inverted (180), left (270) - how far the picture is
 *		turned clockwise on the panel
 *	right_side_up, left_side_up, bottom_up - the Linux/DRM names for how the
 *		panel is mounted; right_side_up is the same as left, left_side_up
 *		the same as right
 * If the desktop comes up upside down, pick the opposite value.
 */
#ifndef _DISPLAY_ROTATION_H
#define _DISPLAY_ROTATION_H


#include <FindDirectory.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>


namespace BPrivate {


static inline int
parse_display_rotation(const char* value)
{
	if (strcasecmp(value, "right") == 0 || strcmp(value, "90") == 0
		|| strcasecmp(value, "cw") == 0
		|| strcasecmp(value, "left_side_up") == 0)
		return 90;
	if (strcasecmp(value, "inverted") == 0 || strcmp(value, "180") == 0
		|| strcasecmp(value, "upside_down") == 0
		|| strcasecmp(value, "bottom_up") == 0)
		return 180;
	if (strcasecmp(value, "left") == 0 || strcmp(value, "270") == 0
		|| strcasecmp(value, "ccw") == 0
		|| strcasecmp(value, "right_side_up") == 0)
		return 270;
	return 0;
}


/*!	Reads the rotation for \a key ("display" or "touch"), in clockwise
	degrees (0, 90, 180 or 270). A missing "touch" entry falls back to
	"display"; a missing file means no rotation.
*/
static inline int
get_display_rotation(const char* key)
{
	char path[B_PATH_NAME_LENGTH];
	if (find_directory(B_USER_SETTINGS_DIRECTORY, -1, false, path,
			sizeof(path)) != B_OK) {
		return 0;
	}
	strlcat(path, "/display_rotation", sizeof(path));

	FILE* file = fopen(path, "r");
	if (file == NULL)
		return 0;

	int display = 0;
	int touch = -1;
	char line[128];
	while (fgets(line, sizeof(line), file) != NULL) {
		char* hash = strchr(line, '#');
		if (hash != NULL)
			*hash = '\0';

		char name[32];
		char value[32];
		int count = sscanf(line, "%31s %31s", name, value);
		if (count == 1) {
			// a bare value means the display rotation
			display = parse_display_rotation(name);
		} else if (count == 2) {
			if (strcasecmp(name, "display") == 0)
				display = parse_display_rotation(value);
			else if (strcasecmp(name, "touch") == 0)
				touch = parse_display_rotation(value);
		}
	}
	fclose(file);

	if (strcmp(key, "touch") == 0 && touch >= 0)
		return touch;
	return display;
}


}	// namespace BPrivate


#endif	// _DISPLAY_ROTATION_H
