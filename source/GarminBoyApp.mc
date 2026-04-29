using Toybox.Application as Application;
using Toybox.WatchUi as WatchUi;

class GarminBoyApp extends Application.AppBase {
    var _emulator as Emulator;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        _emulator = new Emulator();
        _emulator.init();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view     = new GarminBoyView(_emulator);
        var delegate = new GarminBoyDelegate(_emulator.getJoypad());
        return [view, delegate];
    }

    function onStop(state as Dictionary?) as Void {
    }
}
