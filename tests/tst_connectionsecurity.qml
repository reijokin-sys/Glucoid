// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
TestCase {
    name: "ConnectionSecurity"
    visible: true
    width: 640; height: 640
    when: windowShown
    Loader { id: loader; source: "../plasmoid/fi.reijo.glucoid/contents/ui/configGeneral.qml" }
    function find(parent, name) {
        if (parent.objectName === name) return parent
        for (let i=0; parent.children && i<parent.children.length; i++) {
            const child=find(parent.children[i],name); if (child) return child
        }
        return null
    }
    function init() {
        loader.item.cfg_source="nightscout"
        loader.item.cfg_url="https://nightscout.example"
        loader.item.cfg_wireguardInterface="wg0"
        loader.item.cfg_authMode="token"
        loader.item.cfg_token=""
        loader.item.cfg_credentialScope=""
    }
    function test_nightscoutDoesNotRequireInterface() {
        verify(!find(loader.item,"wireguardField").visible)
        compare(find(loader.item,"sourceCombo").currentText,"Nightscout / HTTPS")
    }
    function test_jugglucoMentionsAndRequiresWireguard() {
        loader.item.cfg_source="juggluco"
        verify(find(loader.item,"wireguardField").visible)
        tryVerify(function() { return find(loader.item,"sourceCombo").currentText.indexOf("WireGuard")>=0 },500)
    }
    function test_addressEditClearsCredentialAndScope() {
        loader.item.cfg_token="LAB";loader.item.cfg_credentialScope="previous"
        const url=find(loader.item,"urlField");url.forceActiveFocus();url.cursorPosition=url.text.length;keyClick("a")
        compare(loader.item.cfg_token,"");compare(loader.item.cfg_credentialScope,"")
    }
    function test_typingCredentialBindsCurrentEndpoint() {
        const field=find(loader.item,"tokenField");field.forceActiveFocus();keyClick("a")
        compare(loader.item.cfg_token,"a");compare(loader.item.cfg_credentialScope.length,64)
    }
    function test_sourceChangeClearsCredential() {
        loader.item.cfg_token="LAB";loader.item.cfg_credentialScope="previous"
        const combo=find(loader.item,"sourceCombo");combo.currentIndex=0;combo.activated(0)
        compare(loader.item.cfg_token,"");compare(loader.item.cfg_credentialScope,"")
    }
    function test_legacyHttpsChoosesIndependentNightscout() {
        loader.item.cfg_source="legacy";compare(find(loader.item,"sourceCombo").currentText,"Nightscout / HTTPS")
        loader.item.cfg_url="http://10.77.0.2:17580"
        verify(find(loader.item,"sourceCombo").currentText.indexOf("WireGuard")>=0)
    }
}
