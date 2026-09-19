// Offline tests: no network calls, file uploads, installs or restarts.
const fs = require('fs'), path = require('path'), vm = require('vm'), assert = require('assert');
function observable(value) { return function (next) { if (arguments.length) value = next; return value; }; }
let calls, input, visible;
const context = {
    ko: {observable, observableArray: observable, pureComputed: f => f},
    OCTOPRINT_VIEWMODELS: [],
    document: {getElementById: id => {
        assert.equal(id, 'settings_plugin_pluginmanager_repositorydialog_upload'); return input;
    }},
    $: arg => { if (typeof arg === 'function') return arg(); return {is: () => visible}; }
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../octoprint_manual_multicolor_ps3/static/js/manual_multicolor_ps3.js'), 'utf8'), context);
const registration = context.OCTOPRINT_VIEWMODELS[0];
assert(registration.optional.includes('pluginManagerViewModel'));
function fixture() {
    calls=[]; visible=false;
    input={type:'file', disabled:false, showPicker: () => calls.push('picker'), click: () => calls.push('click')};
    const settings={show: tab => {assert.equal(tab, 'settings_plugin_pluginmanager'); calls.push('settings');}};
    const login={hasPermission: () => true};
    const printer={isBusy: observable(false)};
    const access={permissions:{PLUGIN_PLUGINMANAGER_INSTALL:'install', PLUGIN_PLUGINMANAGER_MANAGE:'manage'}};
    const manager={working:observable(false), pipAvailable:observable(true), safeMode:observable(false), throttled:observable(false),
        showRepository: () => {calls.push('repository'); visible=true;}};
    const model=new registration.construct([settings,login,printer,access,manager]);
    return {model,settings,login,printer,access,manager};
}
let f=fixture(); assert(f.model.canUpdatePlugin()); f.model.openPluginUpdate();
assert.deepEqual(calls, ['settings','repository','picker']);
assert.match(f.model.updateMessage(), /click Install/);
f=fixture(); delete input.showPicker; f.model.openPluginUpdate();
assert.deepEqual(calls, ['settings','repository','click']);
for(const block of ['permissions','busy','working','pip','safe','throttled']) {
    f=fixture();
    if(block==='permissions') f.login.hasPermission=() => false;
    if(block==='busy') f.printer.isBusy(true);
    if(block==='working') f.manager.working(true);
    if(block==='pip') f.manager.pipAvailable(false);
    if(block==='safe') f.manager.safeMode(true);
    if(block==='throttled') f.manager.throttled(true);
    assert(!f.model.canUpdatePlugin(),block); f.model.openPluginUpdate(); assert.deepEqual(calls,[],block);
}
f=fixture(); f.manager.showRepository=() => calls.push('authentication');
f.model.openPluginUpdate(); assert.deepEqual(calls,['settings','authentication']);
assert.match(f.model.updateMessage(),/authentication/);
f=fixture(); input=null; f.model.openPluginUpdate(); assert.match(f.model.updateMessage(), /Browse/);
f=fixture(); input.showPicker=() => {throw new Error('NotAllowedError');};
f.model.openPluginUpdate(); assert.match(f.model.updateMessage(), /Browse/);
f=fixture(); input.disabled=true; f.model.openPluginUpdate(); assert(!calls.includes('picker'));
const missing=new registration.construct([]); assert(!missing.canUpdatePlugin());
console.log('PASS: one-click picker, legacy click fallback, permissions, busy/paused guard, installer availability, reauthentication/restrictions, blocked browser, missing manager/input; no automatic install');
