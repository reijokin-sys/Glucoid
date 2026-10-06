/*
 * Glucoid - configuration dialog pages
 * Copyright (C) 2026  Reijo Kinnunen
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Without this file Plasma shows only its own standard pages (Keyboard
 * Shortcuts, About) and the actual settings page never appears.
 */

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Connection"
        icon: "network-connect"
        source: "configGeneral.qml"
    }
}
