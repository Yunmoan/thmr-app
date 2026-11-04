class SharedRadioStream {
  Uri? get spectrumUri => null;

  Future<Uri> activate(String sourceUrl) async =>
      throw UnsupportedError('Local radio relay is unavailable');

  void stop() {}
}

final sharedRadioStream = SharedRadioStream();
