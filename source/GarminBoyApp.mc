using Toybox.Application as Application;
using Toybox.WatchUi as WatchUi;

class GarminBoyApp extends Application.AppBase {
    var _emulator;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        _emulator = new Emulator();
        _emulator.init();
    }

    function getInitialView() {
        var view     = new GarminBoyView(_emulator);
        var delegate = new GarminBoyDelegate(_emulator.getJoypad());
        return [view, delegate];
    }

    function onStop(state) {
    }
}
