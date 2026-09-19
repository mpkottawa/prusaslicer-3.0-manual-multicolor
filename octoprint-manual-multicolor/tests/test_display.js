const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
function observable(value) { return function (next) { if (arguments.length) value = next; return value; }; }
let navbarLabels = [];
const context = {
    ko: { observable, observableArray: observable, pureComputed: f => f },
    OCTOPRINT_VIEWMODELS: [],
    $: arg => {
        if (typeof arg === 'function') return arg();
        let label;
        const chain = { selector: arg, css: () => chain, toggleClass: () => chain, attr: () => chain,
            empty: () => { if (arg === '#ps3-manual-colour-navbar-slots') navbarLabels = []; return chain; },
            addClass: () => chain, text: value => { label = value; return chain; },
            appendTo: parent => { if (parent.selector === '#ps3-manual-colour-navbar-slots') navbarLabels.push(label); return chain; } };
        return chain;
    }
};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../octoprint_manual_multicolor_ps3/static/js/manual_multicolor_ps3.js'), 'utf8'), context);
const model = new context.OCTOPRINT_VIEWMODELS[0].construct([]);
const state = {
    initial_colour: '#000AFF', loaded_colour: '#000AFF', current_change: 0,
    schedule: [{ number: 1, layer: 1, z: 0.2, colour: '#E92233' }, { number: 2, layer: 2, z: 0.4, colour: '#000AFF' }],
    layer_colours: [{ layer: 1, colours: ['#000AFF', '#E92233'] }]
};
model.applyState(state);
assert.equal(model.initialColour(), 'Blue');
assert.equal(model.nextColour(), 'Red');
assert.equal(model.tabStatus(), 'Current: Blue | Next: Red | Change 0 of 2');
assert.equal(model.layerRows()[0].colours[1].colour, 'Red');
assert.equal(model.layerRows()[0].colours[1].swatch, '#e92233');
assert.equal(model.schedule()[0].swatch, '#000aff');
model.applyState({...state, current_change: 1, waiting_for_change: true});
assert.equal(model.tabStatus(), 'Load: Red | Next: Blue | Change 1 of 2');
model.applyState({...state, current_change: 1, loaded_colour: '#E92233'});
assert.equal(model.tabStatus(), 'Current: Red | Next: Blue | Change 1 of 2');
model.applyState({...state, current_change: 2});
assert.equal(model.nextColour(), 'None');
assert.equal(model.colourName('Ocean Blue'), 'Ocean Blue');
assert.equal(model.colourName('#FFFFFF'), 'White');
model.onDataUpdaterPluginMessage('manual_multicolor_ps3', {action: 'prompt', colour: '#E92233'});
assert.equal(model.colourStatus(), 'CHANGE: Red');
console.log('PASS: start, pause, resume, final change, readable labels, exact swatches, prompts');
model.applyState({...state, used_colours: [{slot: 1, colour: '#000AFF'}, {slot: 3, colour: '#E92233'}, {slot: 5, colour: '#00FF00'}], layer_colours: Array.from({length: 200}, (_, i) => ({layer: i + 1, colours: ['#000AFF']}))});
assert.equal(model.usedColours().length, 3);
assert.equal(model.usedColours()[2].label, 'Green');
assert.equal(model.layerRows().length, 200);
assert.equal(model.layerRows()[0].layer, 200);
assert.equal(model.layerRows()[199].layer, 1);
console.log('PASS: used slots only, 200-layer full-stack data');
assert.equal(model.layerRows()[0].singleColour, true);
assert.equal(model.layerRows()[199].singleColour, false); // scheduled change stays readable
model.applyState({...state, schedule: [], layer_colours: [{layer: 1, colours: ['Black', 'Green', 'Yellow']}, {layer: 2, colours: ['Yellow', 'Black', 'Green']}].concat(Array.from({length: 20}, (_, i) => ({layer: i + 3, colours: ['Green']})))});
assert.equal(model.layerRows().filter(r => r.singleColour).length, 20);
assert.equal(model.layerRows().filter(r => !r.singleColour).length, 2);
console.log('PASS: 22-layer plan keeps 20 body rows compact and both multicolour rows readable');
const paletteState = {...state, file_colours: [
    {slot: 1, colour: '#000AFF', used: true},
    {slot: 2, colour: '#E92233', used: true},
    {slot: 3, colour: '#FFFFFF', used: false}
]};
model.applyState(paletteState);
assert.equal(model.fileColours().length, 3);
assert.equal(model.fileColours().filter(s => s.flashing).length, 0);
model.applyState({...paletteState, print_active: true});
assert.equal(model.fileColours()[0].flashing, true);
assert.equal(model.activeLabel(), 'PRINTING: Blue');
assert.equal(model.fileColours()[0].label, 'Blue');
model.onDataUpdaterPluginMessage('manual_multicolor_ps3', {action: 'next', colour: '#E92233'});
assert.equal(model.fileColours()[0].flashing, true); // M117 alone doesn't change active slot
model.applyState({...paletteState, print_active: true, waiting_for_change: true, current_change: 1});
assert.equal(model.fileColours()[0].flashing, false);
assert.equal(model.fileColours()[1].flashing, true);
assert.equal(model.activeLabel(), 'LOAD: Red');
model.applyState({...paletteState, print_active: true, loaded_colour: '#E92233', current_change: 1});
assert.equal(model.fileColours()[1].flashing, true);
assert.equal(model.activeLabel(), 'PRINTING: Red');
model.applyState({...paletteState, print_active: false});
assert.equal(model.fileColours().filter(s => s.flashing).length, 0);
assert.equal(model.activeLabel(), 'READY: Blue');
console.log('PASS: all file slots, idle, print start, pre-change notice, M600, resume and stop flashing');
const fiveSlots = [
    {slot: 1, colour: '#000000', used: true},
    {slot: 2, colour: '#FFFF00', used: true},
    {slot: 3, colour: '#008000', used: true},
    {slot: 4, colour: '#FF0000', used: false},
    {slot: 5, colour: '#FFFF00', used: false}
];
model.applyState({...state, file_colours: fiveSlots, loaded_colour: 'Yellow', print_active: true});
assert.equal(model.fileColours().map(s => s.unused).join(','), 'false,false,false,true,true');
assert.equal(model.fileColours().map(s => s.label).join(','), 'Black,Yellow,Green,Red,Yellow');
assert.deepEqual(navbarLabels, ['Black', 'Yellow', 'Green']);
assert.equal(model.fileColours()[1].flashing, true);
assert.equal(model.fileColours()[4].flashing, false);
assert.match(model.fileColours()[4].title, /Not used in this print/);
model.applyState({...state, file_colours: fiveSlots, loaded_colour: 'Red', print_active: true});
assert.equal(model.fileColours().filter(s => s.flashing).length, 0);
model.applyState({...state, file_colours: [{slot: 1, colour: '#000000', used: null}]});
assert.equal(model.fileColours()[0].unused, false);
const css = fs.readFileSync(path.join(__dirname, '../octoprint_manual_multicolor_ps3/static/css/manual_multicolor_ps3.css'), 'utf8');
assert.match(css, /border-top: 1px solid #000/);
assert.match(css, /\.ps3-manual-colour-slot\.is-unused::after/);
assert.match(css, /pointer-events: none/);
assert.match(css, /transparent calc\(50% - 2px\)/);
assert.match(css, /prefers-reduced-motion/);
assert.match(css, /\.ps3-manual-colour-now\.is-flashing/);
console.log('PASS: T4/T5 crossed out, duplicate used Yellow highlighted correctly, unknown usage retained, separators and X overlay present');
console.log('PASS: colour-only labels and prominent PRINTING/LOAD/READY indicator with reduced-motion support');
model.applyState({...state, file_colours: [{slot: 1, colour: '#0000FF', used: true}]});
assert.deepEqual(navbarLabels, ['Blue']); // Previous file palette must not linger.
console.log('PASS: navbar excludes unused slots; full tab keeps red crosses at double stroke width');
