/*
 * Glucoid - settings dialog
 * Copyright (C) 2026  Reijo Kinnunen
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Only the essentials are visible: the API address, how to authenticate,
 * the credential, the display unit and the four colour thresholds. The poll
 * interval and the stale limit are behind "Advanced". Values are stored in
 * the widget's own configuration (Plasma applet config, mode 0600).
 */

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts

Item {
    id: page

    property alias cfg_url: urlField.text
    property alias cfg_token: tokenField.text
    property alias cfg_unitsInMmol: unitsBox.checked
    property alias cfg_interval: intervalBox.value
    property alias cfg_ageLimit: ageLimitBox.value

    // Plasma sets these from the schema defaults in contents/config/main.xml;
    // declaring them keeps the page in sync with the schema (and silences
    // "does not have a property called cfg_*Default" warnings).
    property string title
    property string cfg_urlDefault
    property string cfg_authModeDefault: "token"
    property string cfg_tokenDefault
    property int cfg_intervalDefault: 60
    // The colour thresholds have no defaults: 0 means "not set".
    property real cfg_highDefault: 0
    property real cfg_lowDefault: 0
    property real cfg_targetTopDefault: 0
    property real cfg_targetBottomDefault: 0
    property int cfg_ageLimitDefault: 20
    property bool cfg_unitsInMmolDefault: true

    property string cfg_authMode: "token"
    property real cfg_high: 0
    property real cfg_low: 0
    property real cfg_targetTop: 0
    property real cfg_targetBottom: 0

    readonly property string credentialLabel: page.cfg_authMode === "apisecret"
                                             ? "API secret" : "Access token"

    // Threshold fields: an empty field means "not set" (0). Two things must
    // hold at the same time (both reported by the user on 2026-10-06):
    //   1. a cleared or edited field must be committed even when the settings
    //      dialog is accepted while the field still has focus - so the value
    //      is written on every edit (onTextEdited), not only on
    //      editingFinished;
    //   2. the text must not be rewritten while the user is typing, otherwise
    //      an intermediate state like "3." is normalised to "3" mid-edit and
    //      the value can no longer be edited. That is why the text is filled
    //      through a Binding that is switched off while the field has focus
    //      (see the Binding elements below) instead of a plain `text:` binding.
    // The value is stored as a number. The field shows it with the decimal
    // separator of the system locale (a comma in Finnish) and accepts either
    // separator when typing: a DoubleValidator only accepts the separator of
    // its locale, which is why "3.5" could not be typed at all with the
    // Finnish formats (the user's report on 2026-10-06).
    readonly property string decimalSeparator: Qt.locale().decimalPoint

    function formatThreshold(value) {
        // JS Number.toString() always uses "."; show the locale's separator
        return value.toString().replace(".", page.decimalSeparator)
    }

    function commitThreshold(textValue, currentValue) {
        if (textValue.length === 0)
            return 0;
        const v = parseFloat(textValue.replace(",", "."));
        return isNaN(v) ? currentValue : v;
    }

    implicitWidth: 440
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        QQC.Label {
            text: "<b>Nightscout</b>"
            textFormat: Text.RichText
        }

        QQC.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Nightscout site: enter your site address and an access token "
                  + "(or the API secret).<br>"
                  + "<b>Juggluco</b>: enter the address of the phone's web server, "
                  + "e.g. <code>http://192.168.1.23:17580</code>, and the token you "
                  + "set in Juggluco's web server settings - or choose "
                  + "<i>No authentication</i> if the server does not require one."
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 6

            QQC.Label { text: "Address" }
            QQC.TextField {
                id: urlField
                Layout.fillWidth: true
                placeholderText: "https://example.nightscout.example or http://phone:17580"
            }

            QQC.Label { text: "Authentication" }
            QQC.ComboBox {
                id: authCombo
                Layout.fillWidth: true
                textRole: "text"
                valueRole: "value"
                model: [
                    { text: "Access token", value: "token" },
                    { text: "API secret", value: "apisecret" },
                    { text: "No authentication", value: "none" }
                ]
                currentIndex: indexOfValue(page.cfg_authMode)
                onActivated: page.cfg_authMode = currentValue
            }

            QQC.Label { text: page.credentialLabel; visible: page.cfg_authMode !== "none" }
            QQC.TextField {
                id: tokenField
                Layout.fillWidth: true
                visible: page.cfg_authMode !== "none"
                echoMode: TextInput.Password
                placeholderText: "required for Nightscout sites"
            }
        }

        QQC.CheckBox {
            id: unitsBox
            text: "Show readings as mmol/l (otherwise mg/dl)"
        }

        QQC.Label {
            text: "<b>Colour thresholds</b> (in the same unit as the display)"
            textFormat: Text.RichText
            Layout.topMargin: 4
        }

        GridLayout {
            columns: 4
            columnSpacing: 10
            rowSpacing: 6

            QQC.Label { text: "Low" }
            QQC.TextField {
                id: lowField
                objectName: "lowField"
                Layout.preferredWidth: 70
                // both "." and "," are accepted (see commitThreshold)
                validator: RegularExpressionValidator {
                    regularExpression: /^[0-9]*[.,]?[0-9]*$/
                }
                onTextEdited: page.cfg_low = page.commitThreshold(text, page.cfg_low)
                onEditingFinished: page.cfg_low = page.commitThreshold(text, page.cfg_low)
            }
            QQC.Label { text: "High" }
            QQC.TextField {
                id: highField
                objectName: "highField"
                Layout.preferredWidth: 70
                // both "." and "," are accepted (see commitThreshold)
                validator: RegularExpressionValidator {
                    regularExpression: /^[0-9]*[.,]?[0-9]*$/
                }
                onTextEdited: page.cfg_high = page.commitThreshold(text, page.cfg_high)
                onEditingFinished: page.cfg_high = page.commitThreshold(text, page.cfg_high)
            }

            QQC.Label { text: "Target bottom" }
            QQC.TextField {
                id: bottomField
                objectName: "bottomField"
                Layout.preferredWidth: 70
                // both "." and "," are accepted (see commitThreshold)
                validator: RegularExpressionValidator {
                    regularExpression: /^[0-9]*[.,]?[0-9]*$/
                }
                onTextEdited: page.cfg_targetBottom = page.commitThreshold(text, page.cfg_targetBottom)
                onEditingFinished: page.cfg_targetBottom = page.commitThreshold(text, page.cfg_targetBottom)
            }
            QQC.Label { text: "Target top" }
            QQC.TextField {
                id: topField
                objectName: "topField"
                Layout.preferredWidth: 70
                // both "." and "," are accepted (see commitThreshold)
                validator: RegularExpressionValidator {
                    regularExpression: /^[0-9]*[.,]?[0-9]*$/
                }
                onTextEdited: page.cfg_targetTop = page.commitThreshold(text, page.cfg_targetTop)
                onEditingFinished: page.cfg_targetTop = page.commitThreshold(text, page.cfg_targetTop)
            }
        }

        QQC.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            textFormat: Text.RichText
            text: "Low or High: the number turns red. Outside the target range: "
                  + "the number turns amber.<br>These four fields have no defaults - "
                  + "leave a field empty and that warning is simply not used "
                  + "(the value is then shown in the normal text colour)."
        }

        QQC.CheckBox {
            id: advancedBox
            text: "Advanced"
            Layout.topMargin: 4
        }

        GridLayout {
            visible: advancedBox.checked
            columns: 2
            columnSpacing: 10
            rowSpacing: 6

            QQC.Label { text: "Poll interval (s)" }
            QQC.SpinBox {
                id: intervalBox
                from: 15
                to: 3600
                stepSize: 15
                editable: true
            }

            QQC.Label { text: "Stale after (min, 0 = never)" }
            QQC.SpinBox {
                id: ageLimitBox
                from: 0
                to: 999
                stepSize: 5
                editable: true
            }
        }
    }

    // The threshold fields get their text from the configuration, but the
    // binding is switched off while the field has focus. Otherwise every
    // keystroke would write the value back into the field and destroy what is
    // being typed ("3.5" + backspace became "3" instead of "3.").
    Binding {
        target: lowField
        property: "text"
        value: page.cfg_low > 0 ? page.formatThreshold(page.cfg_low) : ""
        when: !lowField.activeFocus
        // keep what is in the field when the binding switches off
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: highField
        property: "text"
        value: page.cfg_high > 0 ? page.formatThreshold(page.cfg_high) : ""
        when: !highField.activeFocus
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: bottomField
        property: "text"
        value: page.cfg_targetBottom > 0 ? page.formatThreshold(page.cfg_targetBottom) : ""
        when: !bottomField.activeFocus
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: topField
        property: "text"
        value: page.cfg_targetTop > 0 ? page.formatThreshold(page.cfg_targetTop) : ""
        when: !topField.activeFocus
        restoreMode: Binding.RestoreNone
    }
}
