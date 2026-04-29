using Toybox.Application as Application;
using Toybox.WatchUi as WatchUi;
using Toybox.Lang as Lang;
using Toybox.System as Sys;

class GarminBoyApp extends Application.AppBase {
    var _emulator;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        try {
            _emulator = new Emulator();
            _emulator.init();
            Sys.println("init ok");
        } catch (ex instanceof Lang.Exception) {
            Sys.println("CRASH onStart: " + ex.getErrorMessage());
        }
    }

    function getInitialView() {
        var view     = new GarminBoyView(_emulator);
        var delegate = new GarminBoyDelegate(_emulator.getJoypad());
        return [view, delegate];
    }

    function onStop(state) {
    }
}
