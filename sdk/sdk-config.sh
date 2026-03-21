#!/bin/bash
# ================================================================
# KSDOS SDK Configuration Script (Linux/Mac)
# Configures environment variables for PS1 and DOOM SDKs
# ================================================================

echo "[KSDOS SDK Configuration]"
echo "============================"

# Set root directory
KSDOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# SDK paths
PS1_SDK="$KSDOS_ROOT/sdk/psyq"
DOOM_SDK="$KSDOS_ROOT/sdk/gold4"

echo "Setting up SDK paths..."
echo "  PS1 SDK: $PS1_SDK"
echo "  DOOM SDK: $DOOM_SDK"

# Export environment variables
export PS1_SDK="$PS1_SDK"
export DOOM_SDK="$DOOM_SDK"
export KSDOS_ROOT="$KSDOS_ROOT"

# Create include paths
export PS1_INC="$PS1_SDK/include"
export DOOM_INC="$DOOM_SDK/include"

# Create library paths  
export PS1_LIB="$PS1_SDK/lib"
export DOOM_LIB="$DOOM_SDK/lib"

# Add to PATH
export PATH="$PS1_SDK/bin:$DOOM_SDK/bin:$PATH"

echo
echo "Environment variables configured:"
echo "  PS1_SDK    = $PS1_SDK"
echo "  DOOM_SDK   = $DOOM_SDK"
echo "  PS1_INC    = $PS1_INC"
echo "  DOOM_INC   = $DOOM_INC"
echo "  PS1_LIB    = $PS1_LIB"
echo "  DOOM_LIB   = $DOOM_LIB"
echo
echo "SDK configuration complete!"
echo "You can now build PS1 and DOOM games using the local SDKs."
echo

# Add to shell profile if requested
if [ "$1" = "--permanent" ]; then
    PROFILE="$HOME/.bashrc"
    if [ -f "$HOME/.zshrc" ]; then
        PROFILE="$HOME/.zshrc"
    fi
    
    echo "Adding SDK configuration to $PROFILE..."
    
    cat >> "$PROFILE" << 'EOF'

# KSDOS SDK Configuration
export PS1_SDK="$KSDOS_ROOT/sdk/psyq"
export DOOM_SDK="$KSDOS_ROOT/sdk/gold4"
export KSDOS_ROOT="$KSDOS_ROOT"
export PS1_INC="$PS1_SDK/include"
export DOOM_INC="$DOOM_SDK/include"
export PS1_LIB="$PS1_SDK/lib"
export DOOM_LIB="$DOOM_SDK/lib"
export PATH="$PS1_SDK/bin:$DOOM_SDK/bin:$PATH"
EOF
    
    echo "SDK configuration added to $PROFILE"
    echo "Restart your terminal or run 'source $PROFILE' to apply changes."
fi
