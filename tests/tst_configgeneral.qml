/*
 * Glucoid - regression tests for the settings page
 * Copyright (C) 2026  reijo
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Run from the project root (works in any locale):
 *
 *   /usr/lib/qt6/bin/qmltestrunner -input tests/tst_configgeneral.qml
 *   LC_ALL=fi_FI.UTF-8 /usr/lib/qt6/bin/qmltestrunner -input tests/tst_configgeneral.qml
 *
 * Background - three reports on 2026-10-06:
 *   1. a threshold value could be written but never removed;
 *   2. after the first fix, an existing value could not be edited digit by
 *      digit (the field's binding rewrote it mid-edit);
 *   3. decimals could not be typed at all, because DoubleValidator only
 *      accepts the separator of the system locale (a comma in Finnish).
 * All three are covered here.
 */

import QtQuick
import QtTest

TestCase {
    name: "ThresholdFields"
    when: windowShown

    Loader {
        id: loader
        source: "../plasmoid/fi.reijo.glucoid/contents/ui/configGeneral.qml"
    }

    // QML has no findChild(), so walk the tree by objectName.
    function findChild(parentItem, name) {
        if (!parentItem || !parentItem.children)
            return null;
        for (let i = 0; i < parentItem.children.length; ++i) {
            const c = parentItem.children[i];
            if (c.objectName === name)
                return c;
            const r = findChild(c, name);
            if (r)
                return r;
        }
        return null;
    }

    // Focused-free field, filled again from the configuration.
    function field(name) {
        const item = findChild(loader.item, name);
        verify(item, name + " was not found");
        item.focus = false;
        wait(50);
        return item;
    }

    // The field shows the value with the separator of the system locale
    // (a comma with the Finnish formats), so comparison is normalised.
    function norm(text) {
        return text.replace(",", ".");
    }

    function type(value) {
        for (let i = 0; i < value.length; ++i)
            keyClick(value[i]);
    }

    // A stored value is shown in the field.
    function test_storedValueIsShown() {
        const page = loader.item;
        const f = field("lowField");
        page.cfg_low = 3.5;
        wait(50);
        compare(norm(f.text), "3.5");
    }

    // Report 2: editing digit by digit, 3.5 -> 3.8. One backspace must remove
    // exactly one character, and the decimal point must survive.
    function test_editExistingValue() {
        const page = loader.item;
        const f = field("lowField");
        page.cfg_low = 3.5;
        wait(50);
        compare(norm(f.text), "3.5");

        f.forceActiveFocus();
        f.cursorPosition = f.text.length;
        keyClick(Qt.Key_Backspace);
        compare(norm(f.text), "3.", "one backspace removes exactly one character");

        keyClick("8");
        compare(norm(f.text), "3.8", "the typed value must stay in the field");
        compare(page.cfg_low, 3.8, "the typed value must be committed");
    }

    // Typing inside an existing value must not be blocked by the validator.
    function test_insertDigitInsideValue() {
        const page = loader.item;
        const f = field("lowField");
        page.cfg_low = 3.5;
        wait(50);
        compare(norm(f.text), "3.5");

        f.forceActiveFocus();
        f.cursorPosition = 2;            // between "3." and "5"
        keyClick("8");
        compare(norm(f.text), "3.85", "typing inside the value must be possible");
    }

    // Report 1: clear the field, then type a new value.
    function test_clearAndTypeNewValue() {
        const page = loader.item;
        const f = field("lowField");
        page.cfg_low = 3.5;
        wait(50);
        compare(norm(f.text), "3.5");

        f.forceActiveFocus();
        f.cursorPosition = f.text.length;
        for (let i = 0; i < 8 && f.text.length > 0; ++i)
            keyClick(Qt.Key_Backspace);
        compare(f.text, "", "the field must be empty");
        compare(page.cfg_low, 0, "clearing must store 0 (= not used)");

        type("7");
        compare(norm(f.text), "7", "a new value can be typed right away");
        compare(page.cfg_low, 7, "the new value must be committed");
    }

    // Report 3a: a decimal with a period (English form) must be accepted.
    function test_typeDecimalWithPeriod() {
        const page = loader.item;
        const f = field("lowField");
        page.cfg_low = 0;
        wait(50);
        compare(f.text, "");

        f.forceActiveFocus();
        type("3.5");
        compare(norm(f.text), "3.5", "a period must be accepted as separator");
        compare(page.cfg_low, 3.5, "the value must be committed");
    }

    // Report 3b: a decimal with a comma (Finnish form) must be accepted.
    function test_typeDecimalWithComma() {
        const page = loader.item;
        const f = field("lowField");
        page.cfg_low = 0;
        wait(50);
        compare(f.text, "");

        f.forceActiveFocus();
        type("3,5");
        compare(norm(f.text), "3.5", "a comma must be accepted as separator");
        compare(page.cfg_low, 3.5, "the value must be committed");
    }
}
