sealed class VoiceCommand {}

class NavigateHome extends VoiceCommand {}

class NavigateSettings extends VoiceCommand {}

class NavigateTranscode extends VoiceCommand {}

class GoBack extends VoiceCommand {}

class StopListening extends VoiceCommand {}

class SwitchTab extends VoiceCommand {
  final int index;
  SwitchTab(this.index);
}

class ScaleRecipe extends VoiceCommand {
  final double factor;
  ScaleRecipe(this.factor);
}

class ConvertUnit extends VoiceCommand {
  final String unit;
  ConvertUnit(this.unit);
}

class NavigateToRecipe extends VoiceCommand {
  final String folder;
  final String filename;
  NavigateToRecipe(this.folder, this.filename);
}

class ToggleCheckbox extends VoiceCommand {
  final int index;
  ToggleCheckbox(this.index);
}

class SetTimer extends VoiceCommand {
  final int seconds;
  final String? label;
  SetTimer(this.seconds, {this.label});
}

class CancelTimer extends VoiceCommand {
  final String? label;
  CancelTimer([this.label]);
}

class PauseTimer extends VoiceCommand {
  final String? label;
  PauseTimer([this.label]);
}

class ResumeTimer extends VoiceCommand {
  final String? label;
  ResumeTimer([this.label]);
}

class HowMuchTimeLeft extends VoiceCommand {}

class ReadIngredients extends VoiceCommand {}

class ReadInstructions extends VoiceCommand {}

class ReadStepN extends VoiceCommand {
  final int stepNumber;
  ReadStepN(this.stepNumber);
}

class ReadNext extends VoiceCommand {}

class ReadPrevious extends VoiceCommand {}

class ReadStop extends VoiceCommand {}

class ReadPause extends VoiceCommand {}

class ReadResume extends VoiceCommand {}

class UnknownCommand extends VoiceCommand {
  final String text;
  UnknownCommand(this.text);
}
