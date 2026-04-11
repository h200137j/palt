import 'dart:async';
class Notifier {
  List<int> state = [];
  Future<void> addEntry(int entry) async {
    state = [entry, ...state];
    await Future.delayed(Duration(milliseconds: 10));
    print("Saved state: $state");
  }
}
void main() {
  final n = Notifier();
  for (int i=1; i<=4; i++) {
    n.addEntry(i);
  }
  print("Main state: ${n.state}");
}
