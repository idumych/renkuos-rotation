/*
 * Touch rotation input_server filter.
 * Distributed under the terms of the MIT License.
 *
 * Touch screens and pen tablets report positions on the physical panel
 * ("be:tablet_x/y", 0..1). With the patched app_server turning the picture,
 * those positions have to be turned the same way. Mice and touchpads send
 * relative movement and are left alone.
 *
 * Reads "touch" (or, if missing, "display") from
 * ~/config/settings/display_rotation once at startup.
 */


#include <new>

#include <Input.h>
#include <InputServerFilter.h>
#include <Message.h>
#include <Screen.h>

#include <math.h>

#include "DisplayRotation.h"


class TouchRotationFilter : public BInputServerFilter {
public:
								TouchRotationFilter();

	virtual	status_t			InitCheck();
	virtual	filter_result		Filter(BMessage* message, BList* outList);

private:
			int					fRotation;
};


TouchRotationFilter::TouchRotationFilter()
	:
	fRotation(BPrivate::get_display_rotation("touch"))
{
}


status_t
TouchRotationFilter::InitCheck()
{
	// stay unloaded when there is nothing to do
	return fRotation != 0 ? B_OK : B_ERROR;
}


filter_result
TouchRotationFilter::Filter(BMessage* message, BList* outList)
{
	switch (message->what) {
		case B_MOUSE_MOVED:
		case B_MOUSE_DOWN:
		case B_MOUSE_UP:
			break;
		default:
			return B_DISPATCH_MESSAGE;
	}

	// only absolute devices (touch screen, pen); mice and touchpads are
	// relative and follow the rotated screen on their own
	if (message->GetInt32("be:device_subtype", 0) != B_TABLET_POINTING_DEVICE)
		return B_DISPATCH_MESSAGE;

	BRect frame = BScreen().Frame();

	float panelX;
	float panelY;
	if (message->FindFloat("be:tablet_x", &panelX) != B_OK
		|| message->FindFloat("be:tablet_y", &panelY) != B_OK) {
		// the tablet driver only adds be:tablet_x/y to B_MOUSE_MOVED;
		// input_server computed "where" from the panel position
		// (x * width, y * height), so turn it back into that
		BPoint where;
		if (message->FindPoint("where", &where) != B_OK
			|| frame.Width() <= 0 || frame.Height() <= 0) {
			return B_DISPATCH_MESSAGE;
		}
		panelX = where.x / frame.Width();
		panelY = where.y / frame.Height();
	}

	// inverse of app_server's logical -> physical mapping
	float x;
	float y;
	switch (fRotation) {
		case 90:
			x = panelY;
			y = 1.0f - panelX;
			break;
		case 180:
			x = 1.0f - panelX;
			y = 1.0f - panelY;
			break;
		case 270:
			x = 1.0f - panelY;
			y = panelX;
			break;
		default:
			return B_DISPATCH_MESSAGE;
	}

	BPoint where(roundf(x * frame.Width()), roundf(y * frame.Height()));
	where.ConstrainTo(frame);

	if (message->ReplacePoint("where", where) != B_OK)
		message->AddPoint("where", where);

	return B_DISPATCH_MESSAGE;
}


extern "C" BInputServerFilter*
instantiate_input_filter()
{
	return new(std::nothrow) TouchRotationFilter();
}
