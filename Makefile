APP_NAME   := AeroTab
LABEL      := local.aerotab
IDENTITY   ?= aerotab-dev
BUILD_APP  := .build/$(APP_NAME).app
INSTALL_APP := $(HOME)/Applications/$(APP_NAME).app
AGENT      := $(HOME)/Library/LaunchAgents/$(LABEL).plist
LOG        := $(HOME)/Library/Logs/aerotab.log
DOMAIN     := gui/$(shell id -u)
DEV_DIR    := $(shell xcode-select -p)/Library/Developer

.PHONY: build app test cert install uninstall restart

build:
	swift build -c release

app: build
	rm -rf $(BUILD_APP)
	mkdir -p $(BUILD_APP)/Contents/MacOS
	cp Resources/Info.plist $(BUILD_APP)/Contents/Info.plist
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" $(BUILD_APP)/Contents/MacOS/$(APP_NAME)
	hash=$$(security find-certificate -c "$(IDENTITY)" -Z | awk '/SHA-1/ {print $$3}'); \
	  [ -n "$$hash" ] || { echo "no '$(IDENTITY)' certificate; run: make cert"; exit 1; }; \
	  codesign --force --timestamp=none --identifier $(LABEL) --sign "$$hash" $(BUILD_APP)

test:
	swift test \
	  -Xswiftc -F -Xswiftc "$(DEV_DIR)/Frameworks" \
	  -Xlinker -F -Xlinker "$(DEV_DIR)/Frameworks" \
	  -Xlinker -rpath -Xlinker "$(DEV_DIR)/Frameworks" \
	  -Xlinker -rpath -Xlinker "$(DEV_DIR)/usr/lib"

cert:
	scripts/create-cert.sh "$(IDENTITY)"

install: app
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents $(dir $(LOG))
	rm -rf $(INSTALL_APP)
	cp -R $(BUILD_APP) $(INSTALL_APP)
	sed -e 's|__BINARY__|$(INSTALL_APP)/Contents/MacOS/$(APP_NAME)|' -e 's|__LOG__|$(LOG)|' \
	  Resources/$(LABEL).plist > $(AGENT)
	launchctl bootstrap $(DOMAIN) $(AGENT)

restart:
	launchctl kickstart -k $(DOMAIN)/$(LABEL)

uninstall:
	-launchctl bootout $(DOMAIN)/$(LABEL) 2>/dev/null
	rm -rf $(INSTALL_APP) $(AGENT)
