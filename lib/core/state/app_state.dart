import 'package:flutter/foundation.dart';

class AppState extends ChangeNotifier {
  bool _isLoading = false;
  bool _isSetup = false;
  String? _errorMessage;
  
  // Getters
  bool get isLoading => _isLoading;
  bool get isSetup => _isSetup;
  String? get errorMessage => _errorMessage;
  
  // Loading state management
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
  
  // Setup state management
  void setSetupComplete(bool setup) {
    if (_isSetup != setup) {
      _isSetup = setup;
      notifyListeners();
    }
  }
  
  // Error state management
  void setError(String? error) {
    if (_errorMessage != error) {
      _errorMessage = error;
      notifyListeners();
    }
  }
  
  void clearError() {
    setError(null);
  }
}

class MealState extends ChangeNotifier {
  int _todayMealCount = 0;
  DateTime? _lastMealTime;
  bool _isSaving = false;
  
  // Getters
  int get todayMealCount => _todayMealCount;
  DateTime? get lastMealTime => _lastMealTime;
  bool get isSaving => _isSaving;
  bool get canRecordMeal => _todayMealCount < 3 && !_isSaving;
  
  // Meal count management
  void updateMealCount(int count) {
    if (_todayMealCount != count) {
      _todayMealCount = count;
      notifyListeners();
    }
  }
  
  // Last meal time management
  void updateLastMealTime(DateTime? time) {
    if (_lastMealTime != time) {
      _lastMealTime = time;
      notifyListeners();
    }
  }
  
  // Saving state management
  void setSaving(bool saving) {
    if (_isSaving != saving) {
      _isSaving = saving;
      notifyListeners();
    }
  }
  
  // Increment meal count after successful recording
  void incrementMealCount() {
    _todayMealCount++;
    _lastMealTime = DateTime.now();
    notifyListeners();
  }
}

class SettingsState extends ChangeNotifier {
  String? _familyCode;
  String? _elderlyName;
  bool _survivalSignalEnabled = false;
  bool _locationTrackingEnabled = false;
  int _alertHours = 12;
  int _foodAlertHours = 8;
  
  // Getters
  String? get familyCode => _familyCode;
  String? get elderlyName => _elderlyName;
  bool get survivalSignalEnabled => _survivalSignalEnabled;
  bool get locationTrackingEnabled => _locationTrackingEnabled;
  int get alertHours => _alertHours;
  int get foodAlertHours => _foodAlertHours;
  
  // Family info management
  void updateFamilyInfo({String? code, String? name}) {
    bool changed = false;
    if (_familyCode != code) {
      _familyCode = code;
      changed = true;
    }
    if (_elderlyName != name) {
      _elderlyName = name;
      changed = true;
    }
    if (changed) notifyListeners();
  }
  
  // Feature toggles
  void setSurvivalSignalEnabled(bool enabled) {
    if (_survivalSignalEnabled != enabled) {
      _survivalSignalEnabled = enabled;
      notifyListeners();
    }
  }
  
  void setLocationTrackingEnabled(bool enabled) {
    if (_locationTrackingEnabled != enabled) {
      _locationTrackingEnabled = enabled;
      notifyListeners();
    }
  }
  
  // Alert settings
  void setAlertHours(int hours) {
    if (_alertHours != hours) {
      _alertHours = hours;
      notifyListeners();
    }
  }
  
  void setFoodAlertHours(int hours) {
    if (_foodAlertHours != hours) {
      _foodAlertHours = hours;
      notifyListeners();
    }
  }
  
  // Load all settings at once
  void loadSettings({
    String? familyCode,
    String? elderlyName,
    bool? survivalSignalEnabled,
    bool? locationTrackingEnabled,
    int? alertHours,
    int? foodAlertHours,
  }) {
    _familyCode = familyCode;
    _elderlyName = elderlyName;
    _survivalSignalEnabled = survivalSignalEnabled ?? false;
    _locationTrackingEnabled = locationTrackingEnabled ?? false;
    _alertHours = alertHours ?? 12;
    _foodAlertHours = foodAlertHours ?? 8;
    notifyListeners();
  }
}