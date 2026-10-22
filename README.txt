NA9AgeSuffix - menambahkan umur postingan di belakang tanggal upload NA9 TikTok.

Hasil: 22/10/26, 04.31  ->  22/10/26, 04.31 - 4h

A) Build dengan Theos (jailbreak, jadi .deb)
   export THEOS=~/theos
   make package
   (ubah bundle id di NA9AgeSuffix.plist kalau TikTok kamu bukan com.zhiliaoapp.musically)

B) Build manual di Mac (untuk TrollFools / sideload, jadi .dylib)
   xcrun -sdk iphoneos clang -arch arm64 -arch arm64e -dynamiclib -fobjc-arc \
     -miphoneos-version-min=14.0 -framework UIKit -framework Foundation \
     -o NA9AgeSuffix.dylib Tweak.m
   ldid -S NA9AgeSuffix.dylib
   Lalu inject NA9AgeSuffix.dylib ke TikTok lewat TrollFools, di samping NA9TikTok.dylib.

Tidak butuh Substrate/ElleKit. Pola tanggal yang dikenali ada di Tweak.m (patterns).

C) Tanpa Mac: GitHub Actions (gratis)
   1. Buat repo baru di GitHub (boleh private), upload semua isi folder ini
      (termasuk folder .github).
   2. Buka tab Actions -> "Build NA9AgeSuffix deb" -> Run workflow.
   3. Setelah selesai, unduh artifact "NA9AgeSuffix": isinya .deb dan .dylib.

D) Dengan Mac: ./build.sh  -> hasil di folder build/
