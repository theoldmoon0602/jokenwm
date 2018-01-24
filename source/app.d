import xcb.xcb;

import std.experimental.logger;

class Client {
public:
	xcb_window_t window;
	this(xcb_window_t window) {
		this.window = window;
	}
}

void main()
{
	auto conn = xcb_connect(null, null);
	if (conn is null || xcb_connection_has_error(conn) != 0) {
		fatal("failed to connect X Server");
	}
	auto screen = xcb_setup_roots_iterator(xcb_get_setup(conn)).data;
	auto root = screen.root;

	uint ROOT_EVENT_MASK = XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT|
		XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY|
		XCB_EVENT_MASK_STRUCTURE_NOTIFY|
		XCB_EVENT_MASK_ENTER_WINDOW|
		XCB_EVENT_MASK_POINTER_MOTION|
		XCB_EVENT_MASK_POINTER_MOTION_HINT|
		XCB_EVENT_MASK_KEY_PRESS|
		XCB_EVENT_MASK_BUTTON_PRESS|
		XCB_EVENT_MASK_BUTTON_RELEASE;

	auto cookie = xcb_change_window_attributes_checked(conn, root, XCB_CW_EVENT_MASK, &ROOT_EVENT_MASK);
	if (xcb_request_check(conn, cookie) !is null) {
		fatal("another window manager is already running");		
	}
	xcb_flush(conn);

	Client[xcb_window_t] clients;
	Client focusing = null;
	int oldx, oldy;
	bool is_moving = false;
	while (true) {
		auto event = xcb_wait_for_event(conn);
		switch (event.response_type) {
		case XCB_MAP_REQUEST:
			auto e = cast(xcb_map_request_event_t*)event;
			foreach (mod_mask; [cast(ushort)0, cast(ushort)XCB_MOD_MASK_2]) {
			xcb_grab_button(conn, 1, e.window,
					XCB_EVENT_MASK_BUTTON_PRESS|
					XCB_EVENT_MASK_BUTTON_RELEASE|
					XCB_EVENT_MASK_POINTER_MOTION,
					XCB_GRAB_MODE_ASYNC,
					XCB_GRAB_MODE_ASYNC,
					e.window, XCB_NONE,
					XCB_BUTTON_INDEX_1,  // LEFT BUTTON
					XCB_MOD_MASK_1|mod_mask);
			xcb_grab_key(conn, 0, root,
					XCB_MOD_MASK_1|mod_mask,
					cast(xcb_keycode_t)24,  //q
					XCB_GRAB_MODE_ASYNC,
					XCB_GRAB_MODE_ASYNC);
			}
			uint window_event = XCB_EVENT_MASK_STRUCTURE_NOTIFY|
				XCB_EVENT_MASK_ENTER_WINDOW;
			xcb_change_window_attributes(conn, e.window, XCB_CW_EVENT_MASK, &window_event);
			xcb_map_window(conn, e.window);
			xcb_flush(conn);

			auto new_client = new Client(e.window);
			clients[e.window] = new_client;
			focusing = new_client;
			break;
		case XCB_BUTTON_PRESS:
			auto e = cast(xcb_button_press_event_t*)event;
			if (e.detail == XCB_BUTTON_INDEX_1 &&
					(e.state & XCB_MOD_MASK_1) && focusing !is null) {
				auto geometry_c = xcb_get_geometry(conn, focusing.window);
				auto geometry_r = xcb_get_geometry_reply(conn, geometry_c, null);
				if (geometry_r is null) {
					break;
				}
				is_moving = true;
				oldx = geometry_r.x - e.root_x;
				oldy = geometry_r.y - e.root_y;
			}
			break;
		case XCB_MOTION_NOTIFY:
			auto e = cast(xcb_motion_notify_event_t*)event;
			if (is_moving && focusing !is null) {
				uint[] values = [
				oldx+e.root_x,
				oldy+e.root_y,
				];
				xcb_configure_window(conn, focusing.window,
						cast(ushort)(XCB_CONFIG_WINDOW_X|XCB_CONFIG_WINDOW_Y),
						values.ptr);
				xcb_flush(conn);
			}
			break;
		case XCB_BUTTON_RELEASE:
			is_moving = false;
			break;
		case XCB_ENTER_NOTIFY:
			auto e = cast(xcb_enter_notify_event_t*)event;
			if (auto client = e.event in clients) {
				uint[] values = [XCB_STACK_MODE_ABOVE];
				xcb_configure_window(conn, client.window, XCB_CONFIG_WINDOW_STACK_MODE, values.ptr);
				xcb_flush(conn);
				focusing = *client;
			}
			break;
		case XCB_KEY_PRESS:
			auto e = cast(xcb_key_press_event_t*)event;
			if (e.detail == 24 &&
					(e.state & XCB_MOD_MASK_1) &&
					focusing !is null) {
				xcb_destroy_window(conn, focusing.window);
				xcb_flush(conn);
				focusing = null;
			}
			break;
		default:
			break;
		}
	}
}
