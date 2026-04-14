import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Wipe all folders in fotos-inspecao', () async {
    // Initialize Supabase
    await Supabase.initialize(
      url: 'http://10.140.50.10:54321',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
    );
    final client = Supabase.instance.client;

    print('Wiping bucket...');
    try {
      final bucket = client.storage.from('fotos-inspecao');
      
      // Function to recursively list and delete
      Future<void> deleteRecursive(String path) async {
        final objects = await bucket.list(path: path);
        for (final obj in objects) {
          final isFolder = obj.id == null || obj.id!.isEmpty;
          final fullPath = path.isEmpty ? obj.name : '$path/${obj.name}';
          
          if (isFolder) {
            print('Entering Folder: $fullPath');
            await deleteRecursive(fullPath);
          } else {
            print('Deleting File: $fullPath');
            await bucket.remove([fullPath]);
          }
        }
      }
      
      await deleteRecursive('');
      print('Wipe complete!');
    } catch (e) {
      print('ERROR WIPING: $e');
    }
  });
}
