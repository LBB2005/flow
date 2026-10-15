PROJECT  = Flow.xcodeproj
SCHEME   = Flow
DEST     = -destination 'platform=macOS,arch=arm64'
DERIVED  = build/DerivedData
APP      = $(DERIVED)/Build/Products/Debug/Flow.app
XCB      = xcodebuild -project $(PROJECT) -scheme $(SCHEME) $(DEST) -derivedDataPath $(DERIVED) -skipMacroValidation

gen:
	xcodegen generate --quiet

build: gen
	$(XCB) -configuration Debug build -quiet

# make test               -> all suites
# make test ONLY=FooTests -> one suite
test: gen
	$(XCB) test -quiet $(if $(ONLY),-only-testing:FlowTests/$(ONLY))

# Real-model tests (downloads ~1.6 GB on first run).
test-models: gen
	TEST_RUNNER_FLOW_MODEL_TESTS=1 $(XCB) test -quiet $(if $(ONLY),-only-testing:FlowTests/$(ONLY))

run: build
	-pkill -x Flow
	open $(APP)

logs:
	log stream --style compact --level debug --predicate 'subsystem == "com.liamblackshawbrown.flow"'

.PHONY: gen build test test-models run logs
