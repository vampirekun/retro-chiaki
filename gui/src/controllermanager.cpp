// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL

#include <controllermanager.h>
#include <settings.h>
#include <QCoreApplication>

#include <QCoreApplication>
#include <QMessageBox>
#include <QByteArray>
#include <QTimer>

#include <cstdio>

#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
#include <SDL.h>
#endif

static QSet<QString> chiaki_motion_controller_guids({
	// Sony on Linux
	"03000000341a00003608000011010000",
	"030000004c0500006802000010010000",
	"030000004c0500006802000010810000",
	"030000004c0500006802000011010000",
	"030000004c0500006802000011810000",
	"030000006f0e00001402000011010000",
	"030000008f0e00000300000010010000",
	"050000004c0500006802000000010000",
	"050000004c0500006802000000800000",
	"050000004c0500006802000000810000",
	"05000000504c415953544154494f4e00",
	"060000004c0500006802000000010000",
	"030000004c050000a00b000011010000",
	"030000004c050000a00b000011810000",
	"030000004c050000c405000011010000",
	"030000004c050000c405000011810000",
	"030000004c050000cc09000000010000",
	"030000004c050000cc09000011010000",
	"030000004c050000cc09000011810000",
	"03000000c01100000140000011010000",
	"050000004c050000c405000000010000",
	"050000004c050000c405000000810000",
	"050000004c050000c405000001800000",
	"050000004c050000cc09000000010000",
	"050000004c050000cc09000000810000",
	"050000004c050000cc09000001800000",
	// Sony on iOS
	"050000004c050000cc090000df070000",
	// Sony on Android
	"050000004c05000068020000dfff3f00",
	"030000004c050000cc09000000006800",
	"050000004c050000c4050000fffe3f00",
	"050000004c050000cc090000fffe3f00",
	"050000004c050000cc090000ffff3f00",
	"35643031303033326130316330353564",
	// Sony on Mac OSx
	"030000004c050000cc09000000000000",
	"030000004c0500006802000000000000",
	"030000004c0500006802000000010000",
	"030000004c050000a00b000000010000",
	"030000004c050000c405000000000000",
	"030000004c050000c405000000010000",
	"030000004c050000cc09000000010000",
	"03000000c01100000140000000010000",
	// Sony on Windows
	"030000004c050000a00b000000000000",
	"030000004c050000c405000000000000",
	"030000004c050000cc09000000000000",
	"03000000250900000500000000000000",
	"030000004c0500006802000000000000",
	"03000000632500007505000000000000",
	"03000000888800000803000000000000",
	"030000008f0e00001431000000000000",
});

static QSet<QPair<int16_t, int16_t>> chiaki_dualsense_controller_ids({
	// in format (vendor id, product id)
	QPair<int16_t, int16_t>(0x054c, 0x0ce6), // DualSense controller
	QPair<int16_t, int16_t>(0x054c, 0x0df2), // DualSense Edge controller
});

static ControllerManager *instance = nullptr;

#define UPDATE_INTERVAL_MS 4

ControllerManager *ControllerManager::GetInstance()
{
	if(!instance)
		instance = new ControllerManager(qApp);
	return instance;
}

ControllerManager::ControllerManager(QObject *parent)
	: QObject(parent)
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	SDL_SetMainReady();
#ifdef SDL_HINT_JOYSTICK_HIDAPI_PS4_RUMBLE
	SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_PS4_RUMBLE, "1");
#endif
#ifdef SDL_HINT_JOYSTICK_HIDAPI_PS5_RUMBLE
	SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_PS5_RUMBLE, "1");
#endif
#ifdef SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS
	SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
#endif
	if(SDL_Init(SDL_INIT_GAMECONTROLLER) < 0)
	{
		const char *err = SDL_GetError();
		QMessageBox::critical(nullptr, "SDL Init", tr("Failed to initialized SDL Gamecontroller: %1").arg(err ? err : ""));
	}

	auto timer = new QTimer(this);
	connect(timer, &QTimer::timeout, this, &ControllerManager::HandleEvents);
	timer->start(UPDATE_INTERVAL_MS);
#endif

	UpdateAvailableControllers();
}

ControllerManager::~ControllerManager()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	SDL_Quit();
#endif
}

void ControllerManager::UpdateAvailableControllers()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	QSet<SDL_JoystickID> current_controllers;
	const bool log_input = qEnvironmentVariableIntValue("RETRO_CHIAKI_LOG_INPUT") != 0;
	if(log_input)
		fprintf(stderr, "[chiaki-input] SDL joysticks=%d\n", SDL_NumJoysticks());
	for(int i=0; i<SDL_NumJoysticks(); i++)
	{
		const bool is_game_controller = SDL_IsGameController(i) == SDL_TRUE;
		SDL_JoystickGUID guid = SDL_JoystickGetDeviceGUID(i);
		char guid_str[33] = {};
		SDL_JoystickGetGUIDString(guid, guid_str, sizeof(guid_str));
		if(log_input)
		{
			char *mapping = is_game_controller ? SDL_GameControllerMappingForDeviceIndex(i) : nullptr;
			fprintf(stderr, "[chiaki-input] device=%d name=\"%s\" guid=%s gamecontroller=%d mapping=%s\n",
				i, SDL_JoystickNameForIndex(i) ? SDL_JoystickNameForIndex(i) : "<unknown>",
				guid_str, is_game_controller ? 1 : 0, mapping ? mapping : "<none>");
			SDL_free(mapping);
		}

		if(!is_game_controller)
			continue;

		// We'll try to identify pads with Motion Control
		if(chiaki_motion_controller_guids.contains(guid_str))
		{
			SDL_Joystick *joy = SDL_JoystickOpen(i);
			if(joy)
			{
				bool no_buttons = SDL_JoystickNumButtons(joy) == 0;
				SDL_JoystickClose(joy);
				if(no_buttons)
					continue;
			}
		}

		current_controllers.insert(SDL_JoystickGetDeviceInstanceID(i));
	}

	if(current_controllers != available_controllers)
	{
		available_controllers = current_controllers;
		emit AvailableControllersUpdated();
	}
#endif
}

void ControllerManager::HandleEvents()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	SDL_Event event;
	while(SDL_PollEvent(&event))
	{
			switch(event.type)
		{
			case SDL_JOYDEVICEADDED:
			case SDL_JOYDEVICEREMOVED:
				UpdateAvailableControllers();
				break;
			case SDL_JOYBUTTONUP:
			case SDL_JOYBUTTONDOWN:
			case SDL_JOYHATMOTION:
			case SDL_JOYAXISMOTION:
			case SDL_CONTROLLERBUTTONUP:
			case SDL_CONTROLLERBUTTONDOWN:
			case SDL_CONTROLLERAXISMOTION:
#if not defined(CHIAKI_ENABLE_SETSU) and SDL_VERSION_ATLEAST(2, 0, 14)
			case SDL_CONTROLLERSENSORUPDATE:
			case SDL_CONTROLLERTOUCHPADDOWN:
			case SDL_CONTROLLERTOUCHPADMOTION:
			case SDL_CONTROLLERTOUCHPADUP:
#endif
				ControllerEvent(event);
				break;
		}
	}

	if(qEnvironmentVariableIntValue("RETRO_CHIAKI_RG34XXSP") != 0)
	{
		SDL_JoystickUpdate();
		for(auto controller : open_controllers)
			controller->PollRG34XXSP();
	}
#endif
}

#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
void ControllerManager::ControllerEvent(SDL_Event event)
{
	int device_id;
	switch(event.type)
	{
		case SDL_CONTROLLERBUTTONDOWN:
		case SDL_CONTROLLERBUTTONUP:
			device_id = event.cbutton.which;
			break;
		case SDL_CONTROLLERAXISMOTION:
			device_id = event.caxis.which;
			break;
		case SDL_JOYBUTTONDOWN:
		case SDL_JOYBUTTONUP:
			device_id = event.jbutton.which;
			break;
		case SDL_JOYHATMOTION:
			device_id = event.jhat.which;
			break;
		case SDL_JOYAXISMOTION:
			device_id = event.jaxis.which;
			break;
#if SDL_VERSION_ATLEAST(2, 0, 14)
		case SDL_CONTROLLERSENSORUPDATE:
			device_id = event.csensor.which;
			break;
		case SDL_CONTROLLERTOUCHPADDOWN:
		case SDL_CONTROLLERTOUCHPADMOTION:
		case SDL_CONTROLLERTOUCHPADUP:
			device_id = event.ctouchpad.which;
			break;
#endif
		default:
			return;
	}
	if(!open_controllers.contains(device_id))
		return;
	open_controllers[device_id]->UpdateState(event);
}
#endif

QSet<int> ControllerManager::GetAvailableControllers()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	return available_controllers;
#else
	return {};
#endif
}

Controller *ControllerManager::OpenController(int device_id)
{
	if(open_controllers.contains(device_id))
		return nullptr;
	auto controller = new Controller(device_id, this);
	open_controllers[device_id] = controller;
	return controller;
}

void ControllerManager::ControllerClosed(Controller *controller)
{
	open_controllers.remove(controller->GetDeviceID());
}

Controller::Controller(int device_id, ControllerManager *manager)
	: QObject(manager), is_dualsense(false)
{
	this->id = device_id;
	this->manager = manager;
	chiaki_orientation_tracker_init(&this->orientation_tracker);
	chiaki_controller_state_set_idle(&this->state);

#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	controller = nullptr;
	for(int i=0; i<SDL_NumJoysticks(); i++)
	{
		if(SDL_JoystickGetDeviceInstanceID(i) == device_id)
		{
			controller = SDL_GameControllerOpen(i);
			if(controller && qEnvironmentVariableIntValue("RETRO_CHIAKI_LOG_INPUT") != 0)
			{
				char *mapping = SDL_GameControllerMapping(controller);
				fprintf(stderr, "[chiaki-input] SDL mapping: %s\n", mapping ? mapping : "<none>");
				SDL_free(mapping);
			}
#if SDL_VERSION_ATLEAST(2, 0, 14)
			if(SDL_GameControllerHasSensor(controller, SDL_SENSOR_ACCEL))
				SDL_GameControllerSetSensorEnabled(controller, SDL_SENSOR_ACCEL, SDL_TRUE);
			if(SDL_GameControllerHasSensor(controller, SDL_SENSOR_GYRO))
				SDL_GameControllerSetSensorEnabled(controller, SDL_SENSOR_GYRO, SDL_TRUE);
#endif
			auto controller_id = QPair<int16_t, int16_t>(SDL_GameControllerGetVendor(controller), SDL_GameControllerGetProduct(controller));
			is_dualsense = chiaki_dualsense_controller_ids.contains(controller_id);
			break;
		}
	}

	ReloadButtonMapping();
	if(manager->GetSettings())
		connect(manager->GetSettings(), &Settings::ControllerButtonMappingUpdated, this, &Controller::ReloadButtonMapping);
#endif
}

Controller::~Controller()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	if(controller)
	{
		// Clear trigger effects, SDL doesn't do it automatically
		const uint8_t clear_effect[10] = { 0 };
		this->SetTriggerEffects(0x05, clear_effect, 0x05, clear_effect);
		SDL_GameControllerClose(controller);
	}
#endif
	manager->ControllerClosed(this);
}

#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
void Controller::ReloadButtonMapping()
{
	button_mapping.clear();
	if(manager->GetSettings())
	{
		auto chiaki_to_sdl = manager->GetSettings()->GetControllerButtonMapping();
		for(auto it = chiaki_to_sdl.begin(); it != chiaki_to_sdl.end(); ++it)
			button_mapping.insert(it.value(), it.key());
	}
	else
	{
		CHIAKI_LOGW(NULL, "ControllerManager has no Settings -- gamepad buttons will not be mapped. This should have been wired up at startup.");
	}
#if SDL_VERSION_ATLEAST(2, 0, 14)
	button_mapping.insert((int)SDL_CONTROLLER_BUTTON_TOUCHPAD, CHIAKI_CONTROLLER_BUTTON_TOUCHPAD);
#endif

	if(qEnvironmentVariableIntValue("RETRO_CHIAKI_LOG_INPUT") != 0)
	{
		for(auto it = button_mapping.begin(); it != button_mapping.end(); ++it)
			fprintf(stderr, "[chiaki-input] source=%d (%s) -> target=%d\n", it.key(),
				Settings::GetSDLButtonName(it.key()).toLocal8Bit().constData(), it.value());
	}
}

void Controller::UpdateState(SDL_Event event)
{
	// The RG34XX-SP path is polled in PollRG34XXSP() so it cannot depend on
	// whether this firmware emits raw joystick events alongside controller
	// events. Ignore all queued translations for that device.
	if(qEnvironmentVariableIntValue("RETRO_CHIAKI_RG34XXSP") != 0)
		return;

	switch(event.type)
	{
		case SDL_CONTROLLERBUTTONDOWN:
		case SDL_CONTROLLERBUTTONUP:
			if(!HandleButtonEvent(event.cbutton))
				return;
			break;
		case SDL_CONTROLLERAXISMOTION:
			if(!HandleAxisEvent(event.caxis))
				return;
			break;
#if SDL_VERSION_ATLEAST(2, 0, 14)
		case SDL_CONTROLLERSENSORUPDATE:
			if(!HandleSensorEvent(event.csensor))
				return;
			break;
		case SDL_CONTROLLERTOUCHPADDOWN:
		case SDL_CONTROLLERTOUCHPADMOTION:
		case SDL_CONTROLLERTOUCHPADUP:
			if(!HandleTouchpadEvent(event.ctouchpad))
				return;
			break;
#endif
		default:
			return;

	}
	emit StateChanged();
}

void Controller::PollRG34XXSP()
{
	if(!controller)
		return;
	SDL_Joystick *joystick = SDL_GameControllerGetJoystick(controller);
	if(!joystick || SDL_JoystickGetAttached(joystick) != SDL_TRUE)
		return;

	ChiakiControllerState next_state;
	chiaki_controller_state_set_idle(&next_state);
	uint32_t raw_buttons = 0;

	auto apply_button = [&](int raw_button, int target) {
		if(SDL_JoystickGetButton(joystick, raw_button) == 0)
			return;
		raw_buttons |= (1u << raw_button);
		if(target == CHIAKI_CONTROLLER_ANALOG_BUTTON_L2)
			next_state.l2_state = 0xff;
		else if(target == CHIAKI_CONTROLLER_ANALOG_BUTTON_R2)
			next_state.r2_state = 0xff;
		else
			next_state.buttons |= (ChiakiControllerButton)target;
	};

	apply_button(3, CHIAKI_CONTROLLER_BUTTON_MOON);        // physical A
	apply_button(4, CHIAKI_CONTROLLER_BUTTON_CROSS);       // physical B
	apply_button(5, CHIAKI_CONTROLLER_BUTTON_BOX);         // physical Y
	apply_button(6, CHIAKI_CONTROLLER_BUTTON_PYRAMID);     // physical X
	apply_button(7, CHIAKI_CONTROLLER_BUTTON_L1);
	apply_button(8, CHIAKI_CONTROLLER_BUTTON_R1);
	apply_button(9, CHIAKI_CONTROLLER_BUTTON_SHARE);       // Select
	apply_button(10, CHIAKI_CONTROLLER_BUTTON_OPTIONS);    // Start
	apply_button(11, CHIAKI_CONTROLLER_BUTTON_PS);         // M
	apply_button(12, CHIAKI_CONTROLLER_BUTTON_L3);
	apply_button(13, CHIAKI_CONTROLLER_ANALOG_BUTTON_L2);
	apply_button(14, CHIAKI_CONTROLLER_ANALOG_BUTTON_R2);
	apply_button(15, CHIAKI_CONTROLLER_BUTTON_R3);

	if(SDL_JoystickNumHats(joystick) > 0)
	{
		const Uint8 hat = SDL_JoystickGetHat(joystick, 0);
		if(hat & SDL_HAT_LEFT)
			next_state.buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_LEFT;
		if(hat & SDL_HAT_RIGHT)
			next_state.buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_RIGHT;
		if(hat & SDL_HAT_UP)
			next_state.buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_UP;
		if(hat & SDL_HAT_DOWN)
			next_state.buttons |= CHIAKI_CONTROLLER_BUTTON_DPAD_DOWN;
	}

	if(SDL_JoystickNumAxes(joystick) >= 4)
	{
		next_state.left_x = SDL_JoystickGetAxis(joystick, 0);
		next_state.left_y = SDL_JoystickGetAxis(joystick, 1);
		next_state.right_x = SDL_JoystickGetAxis(joystick, 2);
		next_state.right_y = SDL_JoystickGetAxis(joystick, 3);
	}

	if((raw_buttons & (1u << 11)) && (raw_buttons & (1u << 10)))
	{
		QCoreApplication::quit();
		return;
	}

	if(chiaki_controller_state_equals(&state, &next_state))
		return;
	state = next_state;

	const QByteArray input_log_path = qgetenv("RETRO_CHIAKI_INPUT_LOG");
	if(!input_log_path.isEmpty())
	{
		FILE *input_log = fopen(input_log_path.constData(), "a");
		if(input_log)
		{
			fprintf(input_log, "raw=0x%08x ps=0x%08x l2=%u r2=%u axes=%d,%d,%d,%d\n",
				raw_buttons, state.buttons, state.l2_state, state.r2_state,
				state.left_x, state.left_y, state.right_x, state.right_y);
			fclose(input_log);
		}
	}

	emit StateChanged();
}

inline void Controller::ApplyMappedButton(int chiaki_target, bool pressed)
{
	// L2/R2 are analog fields (l2_state/r2_state), not bits in the buttons
	// bitmask -- a digital source driving them just goes full-scale on press,
	// same as StreamSession::HandleKeyboardEvent already does for the
	// keyboard-as-controller fallback.
	if(chiaki_target == CHIAKI_CONTROLLER_ANALOG_BUTTON_L2)
		state.l2_state = pressed ? 0xff : 0;
	else if(chiaki_target == CHIAKI_CONTROLLER_ANALOG_BUTTON_R2)
		state.r2_state = pressed ? 0xff : 0;
	else if(pressed)
		state.buttons |= (ChiakiControllerButton)chiaki_target;
	else
		state.buttons &= ~(ChiakiControllerButton)chiaki_target;
}

inline bool Controller::HandleButtonEvent(SDL_ControllerButtonEvent event) {
	if(event.type == SDL_CONTROLLERBUTTONDOWN)
		pressed_buttons.insert((int)event.button);
	else
		pressed_buttons.remove((int)event.button);

	if(qEnvironmentVariableIntValue("RETRO_CHIAKI_LOG_INPUT") != 0)
		fprintf(stderr, "[chiaki-input] button=%d (%s) %s target=%d\n", event.button,
			SDL_GameControllerGetStringForButton((SDL_GameControllerButton)event.button),
			event.type == SDL_CONTROLLERBUTTONDOWN ? "down" : "up",
			button_mapping.value((int)event.button, 0));

	if(pressed_buttons.contains(SDL_CONTROLLER_BUTTON_GUIDE)
			&& pressed_buttons.contains(SDL_CONTROLLER_BUTTON_START))
	{
		fprintf(stderr, "[chiaki-input] M + Start exit chord\n");
		QCoreApplication::quit();
		return false;
	}

	// Which physical button triggers which PS button (including L2/R2) is
	// user-configurable via Settings::GetControllerButtonMapping() (Settings >
	// Controller Button Mapping) -- button_mapping was built from it at
	// construction time.
	if(!button_mapping.contains((int)event.button))
		return false;
	ApplyMappedButton(button_mapping[(int)event.button], event.type == SDL_CONTROLLERBUTTONDOWN);

	return true;
}

inline bool Controller::HandleAxisEvent(SDL_ControllerAxisEvent event) {
	switch(event.axis)
	{
		case SDL_CONTROLLER_AXIS_TRIGGERLEFT:
		case SDL_CONTROLLER_AXIS_TRIGGERRIGHT:
		{
			// This handheld's triggers are plain digital switches under the
			// hood (see Settings::kTriggerLeftSource's doc comment), so which
			// PS button each physical trigger drives is looked up in the same
			// button_mapping as everything else.
			int source = event.axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT ? Settings::kTriggerLeftSource : Settings::kTriggerRightSource;
			if(!button_mapping.contains(source))
				return false;
			uint8_t value = (uint8_t)(event.value >> 7);
			int chiaki_target = button_mapping[source];
			if(chiaki_target == CHIAKI_CONTROLLER_ANALOG_BUTTON_L2)
				state.l2_state = value;
			else if(chiaki_target == CHIAKI_CONTROLLER_ANALOG_BUTTON_R2)
				state.r2_state = value;
			else
				ApplyMappedButton(chiaki_target, value > 0);
			break;
		}
		case SDL_CONTROLLER_AXIS_LEFTX:
			state.left_x = event.value;
			break;
		case SDL_CONTROLLER_AXIS_LEFTY:
			state.left_y = event.value;
			break;
		case SDL_CONTROLLER_AXIS_RIGHTX:
			state.right_x = event.value;
			break;
		case SDL_CONTROLLER_AXIS_RIGHTY:
			state.right_y = event.value;
			break;
		default:
			return false;
	}
	return true;
}

#if SDL_VERSION_ATLEAST(2, 0, 14)
inline bool Controller::HandleSensorEvent(SDL_ControllerSensorEvent event)
{
	switch(event.sensor)
	{
		case SDL_SENSOR_ACCEL:
			state.accel_x = event.data[0] / SDL_STANDARD_GRAVITY;
			state.accel_y = event.data[1] / SDL_STANDARD_GRAVITY;
			state.accel_z = event.data[2] / SDL_STANDARD_GRAVITY;
			break;
		case SDL_SENSOR_GYRO:
			state.gyro_x = event.data[0];
			state.gyro_y = event.data[1];
			state.gyro_z = event.data[2];
			break;
		default:
			return false;
	}
	chiaki_orientation_tracker_update(
		&orientation_tracker, state.gyro_x, state.gyro_y, state.gyro_z,
		state.accel_x, state.accel_y, state.accel_z, event.timestamp * 1000);
	chiaki_orientation_tracker_apply_to_controller_state(&orientation_tracker, &state);
	return true;
}

inline bool Controller::HandleTouchpadEvent(SDL_ControllerTouchpadEvent event)
{
	auto key = qMakePair(event.touchpad, event.finger);
	bool exists = touch_ids.contains(key);
	uint8_t chiaki_id;
	switch(event.type)
	{
		case SDL_CONTROLLERTOUCHPADDOWN:
			if(touch_ids.size() >= CHIAKI_CONTROLLER_TOUCHES_MAX)
				return false;
			chiaki_id = chiaki_controller_state_start_touch(&state, event.x * PS_TOUCHPAD_MAX_X, event.y * PS_TOUCHPAD_MAX_Y);
			touch_ids.insert(key, chiaki_id);
			break;
		case SDL_CONTROLLERTOUCHPADMOTION:
			if(!exists)
				return false;
			chiaki_controller_state_set_touch_pos(&state, touch_ids[key], event.x * PS_TOUCHPAD_MAX_X, event.y * PS_TOUCHPAD_MAX_Y);
			break;
		case SDL_CONTROLLERTOUCHPADUP:
			if(!exists)
				return false;
			chiaki_controller_state_stop_touch(&state, touch_ids[key]);
			touch_ids.remove(key);
			break;
		default:
			return false;
	}
	return true;
}
#endif
#endif

bool Controller::IsConnected()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	return controller && SDL_GameControllerGetAttached(controller);
#else
	return false;
#endif
}

int Controller::GetDeviceID()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	return id;
#else
	return -1;
#endif
}

QString Controller::GetName()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	if(!controller)
		return QString();
	SDL_Joystick *js = SDL_GameControllerGetJoystick(controller);
	SDL_JoystickGUID guid = SDL_JoystickGetGUID(js);
	char guid_str[256];
	SDL_JoystickGetGUIDString(guid, guid_str, sizeof(guid_str));
	return QString("%1 (%2)").arg(SDL_JoystickName(js), guid_str);
#else
	return QString();
#endif
}

ChiakiControllerState Controller::GetState()
{
	return state;
}

void Controller::SetRumble(uint8_t left, uint8_t right)
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	if(!controller)
		return;
	SDL_GameControllerRumble(controller, (uint16_t)left << 8, (uint16_t)right << 8, 5000);
#endif
}

void Controller::SetTriggerEffects(uint8_t type_left, const uint8_t *data_left, uint8_t type_right, const uint8_t *data_right)
{
#if defined(CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER) && SDL_VERSION_ATLEAST(2, 0, 16)
	if(!is_dualsense || !controller)
		return;
	DS5EffectsState_t state;
	SDL_zero(state);
	state.ucEnableBits1 |= (0x04 /* left trigger */ | 0x08 /* right trigger */);
	state.rgucLeftTriggerEffect[0] = type_left;
	SDL_memcpy(state.rgucLeftTriggerEffect + 1, data_left, 10);
	state.rgucRightTriggerEffect[0] = type_right;
	SDL_memcpy(state.rgucRightTriggerEffect + 1, data_right, 10);
	SDL_GameControllerSendEffect(controller, &state, sizeof(state));
#endif
}

bool Controller::IsDualSense()
{
#ifdef CHIAKI_GUI_ENABLE_SDL_GAMECONTROLLER
	if(!controller)
		return false;
	return is_dualsense;
#endif
}
