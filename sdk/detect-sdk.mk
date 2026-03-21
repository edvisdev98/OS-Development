# ================================================================
# KSDOS SDK Detection System
# Automatically detects and configures SDK paths
# ================================================================

# Default SDK paths (relative to project root)
KSDOS_ROOT ?= $(abspath ..)
PS1_SDK_DEFAULT = $(KSDOS_ROOT)/sdk/psyq
DOOM_SDK_DEFAULT = $(KSDOS_ROOT)/sdk/gold4

# SDK detection function
define detect_sdk
$(if $(wildcard $(1)),$(1),$(if $(wildcard $(2)),$(2),$(3)))
endef

# Auto-detect SDK paths
PS1_SDK := $(call detect_sdk,$(PS1_SDK),$(PS1_SDK_DEFAULT),$(error PS1 SDK not found))
DOOM_SDK := $(call detect_sdk,$(DOOM_SDK),$(DOOM_SDK_DEFAULT),$(error DOOM SDK not found))

# SDK validation
define validate_sdk
$(if $(wildcard $(1)/include),,$(error SDK include directory not found: $(1)/include))
$(if $(wildcard $(1)/lib),,$(error SDK lib directory not found: $(1)/lib))
endef

# Validate SDKs
$(eval $(call validate_sdk,$(PS1_SDK)))
$(eval $(call validate_sdk,$(DOOM_SDK)))

# SDK configuration variables
PS1_INC = $(PS1_SDK)/include
PS1_LIB = $(PS1_SDK)/lib
DOOM_INC = $(DOOM_SDK)/include
DOOM_LIB = $(DOOM_SDK)/lib

# Export for sub-makes
export PS1_SDK PS1_INC PS1_LIB
export DOOM_SDK DOOM_INC DOOM_LIB
export KSDOS_ROOT

# Print SDK information
define print_sdk_info
@echo "=== SDK Configuration ==="
@echo "KSDOS_ROOT: $(KSDOS_ROOT)"
@echo "PS1_SDK: $(PS1_SDK)"
@echo "  Include: $(PS1_INC)"
@echo "  Libraries: $(PS1_LIB)"
@echo "DOOM_SDK: $(DOOM_SDK)"
@echo "  Include: $(DOOM_INC)"
@echo "  Libraries: $(DOOM_LIB)"
@echo "========================"
endef

# Auto-configure SDKs if needed
define auto_configure_sdk
$(if $(wildcard $(PS1_SDK)),,$(error PS1 SDK not found at $(PS1_SDK). Run 'make configure-sdk'))
$(if $(wildcard $(DOOM_SDK)),,$(error DOOM SDK not found at $(DOOM_SDK). Run 'make configure-sdk'))
endef
