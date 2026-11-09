// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QString>
bool activeWireguard(const QString &name);
bool bindWireguard(int descriptor,const QString &name);
