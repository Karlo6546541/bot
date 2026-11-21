import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/services/image_store.dart';

void main() {
  test('vrsta reference na sliku', () {
    expect(
      PhotoSource.of(
        'https://x.supabase.co/storage/v1/object/public/loop-images/a.jpg',
      ),
      PhotoSource.network,
    );
    expect(PhotoSource.of('data:image/jpeg;base64,AAAA'), PhotoSource.data);
    expect(PhotoSource.of(r'C:\Users\x\loop_images\a.jpg'), PhotoSource.file);
    expect(PhotoSource.of('/data/user/0/loop/a.jpg'), PhotoSource.file);
  });

  test('putanja datoteke iz javnog URL-a Supabase Storagea', () {
    expect(
      ImageStore.storagePathOf(
        'https://x.supabase.co/storage/v1/object/public/loop-images/abc.png',
      ),
      'abc.png',
    );
    expect(ImageStore.storagePathOf('https://primjer.com/slika.png'), isNull);
  });
}
