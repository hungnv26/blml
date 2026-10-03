# Adds BLML's own licence entry to the Settings acknowledgements pane.
# CocoaPods generates that file from the pods alone; the app itself is
# Apache-2.0 and carries upstream copyright, so it needs an entry too.
# Run from the ios/ directory; the Podfile calls this after every `pod install`.
require 'xcodeproj'

ack_path = 'Tinodios/Settings.bundle/Acknowledgements.plist'
ack = Xcodeproj::Plist.read_from_path(ack_path)
specs = ack['PreferenceSpecifiers']
specs.reject! { |s| s['Title'] == 'BLML' }
# Index 0 is the "This application makes use of..." header.
specs.insert(1, {
  'FooterText' => File.read('acknowledgement-blml.txt', encoding: 'UTF-8') + "\n" + File.read('LICENSE', encoding: 'UTF-8'),
  'License' => 'Apache-2.0',
  'Title' => 'BLML',
  'Type' => 'PSGroupSpecifier',
})
Xcodeproj::Plist.write_to_path(ack, ack_path)
