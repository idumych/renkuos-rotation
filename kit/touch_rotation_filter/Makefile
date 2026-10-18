# Build on Haiku:  make && make install
NAME = touch_rotation
TARGET_DIR = $(shell finddir B_USER_NONPACKAGED_ADDONS_DIRECTORY)/input_server/filters

$(NAME): TouchRotationFilter.cpp DisplayRotation.h
	g++ -O2 -Wall -shared -fPIC -o $@ TouchRotationFilter.cpp -lbe /system/servers/input_server

install: $(NAME)
	mkdir -p "$(TARGET_DIR)"
	cp $(NAME) "$(TARGET_DIR)/"

clean:
	rm -f $(NAME)
