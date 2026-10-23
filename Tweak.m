// NA9AgeSuffix v1.2
// Menambahkan umur postingan ("4h", "3d", ...) di belakang tanggal upload NA9 TikTok:
//   22/10/26, 04.31  ->  22/10/26, 04.31 - 4h
//
// Cara utama : mengait +[TTKHelperTools formattedDateTime:] (milik NA9TikTok.dylib).
//              Method itu menerima NSDate upload dan mengembalikan teks tanggal,
//              jadi umur dihitung dari NSDate aslinya (tanpa parsing teks).
// Cadangan   : mengait UILabel setText:/setAttributedText: dan menempelkan umur bila
//              teksnya berbentuk tanggal (dipakai kalau kait utama gagal terpasang).
// Tambahan v1.2: menyembunyikan kartu kosong "(null)" di hasil pencarian (sisa slot iklan
//              yang isinya dibuang fitur "Remove ads" NA9). Best-effort, lihat NA9HideNullCell.
// Murni Objective-C runtime, tidak butuh Substrate/ElleKit.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static NSRegularExpression *gRegex;
static NSArray<NSDateFormatter *> *gFormatters;
static BOOL gMainHooked = NO;

static NSString *(*orig_formattedDateTime)(id, SEL, NSDate *);
static void (*orig_setText)(id, SEL, NSString *);
static void (*orig_setAttributedText)(id, SEL, NSAttributedString *);

// Umur -> teks singkat: now, 5m, 4h, 3d, 2w, 5mo, 1y
static NSString *NA9AgeString(NSTimeInterval s) {
    if (s < 0) s = 0;
    long m = (long)(s / 60), h = (long)(s / 3600), d = (long)(s / 86400);
    if (s < 60)  return @"now";
    if (m < 60)  return [NSString stringWithFormat:@"%ldm", m];
    if (h < 24)  return [NSString stringWithFormat:@"%ldh", h];
    if (d < 7)   return [NSString stringWithFormat:@"%ldd", d];
    if (d < 30)  return [NSString stringWithFormat:@"%ldw", d / 7];
    if (d < 365) return [NSString stringWithFormat:@"%ldmo", d / 30];
    return [NSString stringWithFormat:@"%ldy", d / 365];
}

// ---------- Kait utama: +[TTKHelperTools formattedDateTime:] ----------
static NSString *new_formattedDateTime(id self, SEL _cmd, NSDate *date) {
    NSString *s = orig_formattedDateTime(self, _cmd, date);
    if (![s isKindOfClass:[NSString class]] || ![date isKindOfClass:[NSDate class]]) return s;
    if (s.length == 0) return s;
    return [NSString stringWithFormat:@"%@ - %@", s, NA9AgeString(-[date timeIntervalSinceNow])];
}

static void NA9TryHookMain(void) {
    @synchronized ([UIApplication class]) {
        if (gMainHooked) return;
        Class c = NSClassFromString(@"TTKHelperTools");
        if (!c) return;
        Method m = class_getClassMethod(c, @selector(formattedDateTime:));
        if (!m) return;
        orig_formattedDateTime = (NSString *(*)(id, SEL, NSDate *))method_getImplementation(m);
        method_setImplementation(m, (IMP)new_formattedDateTime);
        gMainHooked = YES;
        NSLog(@"[NA9AgeSuffix] main hook installed");
    }
}

static void NA9ImageAdded(const struct mach_header *mh, intptr_t slide) {
    if (!gMainHooked) NA9TryHookMain();
}

// ---------- Cadangan: tempel umur pada teks UILabel yang berbentuk tanggal ----------
static NSString *NA9Decorate(NSString *text) {
    if (gMainHooked) return nil;                       // kait utama sudah aktif
    if (![text isKindOfClass:[NSString class]]) return nil;
    NSUInteger len = text.length;
    if (len < 12 || len > 22) return nil;
    unichar c0 = [text characterAtIndex:0];
    if (c0 < '0' || c0 > '9') return nil;
    if ([gRegex firstMatchInString:text options:0 range:NSMakeRange(0, len)] == nil) return nil;
    // Samakan semua jenis spasi (NBSP, narrow NBSP, dll) menjadi spasi biasa
    NSString *norm = [gRegex stringByReplacingMatchesInString:text options:0
                          range:NSMakeRange(0, len) withTemplate:@"$1/$2/$3, $4$5$6"];
    for (NSDateFormatter *f in gFormatters) {
        NSDate *date = [f dateFromString:norm];
        if (date) {
            return [NSString stringWithFormat:@"%@ - %@", text,
                    NA9AgeString(-[date timeIntervalSinceNow])];
        }
    }
    return nil;
}


// ---------- Sembunyikan kartu "(null)" (sisa slot iklan) ----------
static const void *kNA9NullLabelKey = &kNA9NullLabelKey;  // dipasang di UILabel pemicu
static const void *kNA9HiddenByKey  = &kNA9HiddenByKey;   // dipasang di cell: label pemicu

static UICollectionViewCell *NA9EnclosingCell(UIView *v) {
    UIView *p = v;
    for (int i = 0; i < 12 && p; i++, p = p.superview) {
        if ([p isKindOfClass:[UICollectionViewCell class]]) return (UICollectionViewCell *)p;
    }
    return nil;
}

// text == persis "(null)"  -> sembunyikan cell pembungkus label ini.
// label yang sama berganti ke teks lain (cell dipakai ulang) -> tampilkan lagi.
static void NA9HideNullCell(UILabel *label, NSString *text) {
    if (![label isKindOfClass:[UILabel class]]) return;
    BOOL isNull = [text isKindOfClass:[NSString class]] && [text isEqualToString:@"(null)"];
    if (isNull) {
        UICollectionViewCell *cell = NA9EnclosingCell(label);
        if (!cell) return;
        objc_setAssociatedObject(label, kNA9NullLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, kNA9HiddenByKey,
                                 [NSValue valueWithPointer:(__bridge const void *)label],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.hidden = YES;
        cell.userInteractionEnabled = NO;
        return;
    }
    if (objc_getAssociatedObject(label, kNA9NullLabelKey)) {
        objc_setAssociatedObject(label, kNA9NullLabelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UICollectionViewCell *cell = NA9EnclosingCell(label);
        NSValue *owner = cell ? objc_getAssociatedObject(cell, kNA9HiddenByKey) : nil;
        if (owner && owner.pointerValue == (__bridge const void *)label) {
            objc_setAssociatedObject(cell, kNA9HiddenByKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.hidden = NO;
            cell.userInteractionEnabled = YES;
        }
    }
}

static void new_setText(id self, SEL _cmd, NSString *text) {
    NSString *decorated = NA9Decorate(text);
    orig_setText(self, _cmd, decorated ?: text);
    NA9HideNullCell(self, text);
}

static void new_setAttributedText(id self, SEL _cmd, NSAttributedString *text) {
    NSString *decorated = text ? NA9Decorate(text.string) : nil;
    if (decorated) {
        NSMutableAttributedString *m = [text mutableCopy];
        NSDictionary *attrs = text.length ? [text attributesAtIndex:text.length - 1 effectiveRange:NULL] : nil;
        NSString *suffix = [decorated substringFromIndex:text.length];
        [m appendAttributedString:[[NSAttributedString alloc] initWithString:suffix attributes:attrs]];
        text = m;
    }
    orig_setAttributedText(self, _cmd, text);
    NA9HideNullCell(self, text.string);
}

__attribute__((constructor)) static void NA9AgeInit(void) {
    @autoreleasepool {
        NSLog(@"[NA9AgeSuffix] loaded");

        // Kelompok: 1=dd 2=MM 3=yy(yy) 4=jam 5=pemisah 6=menit; spasi di antaranya longgar
        gRegex = [NSRegularExpression
            regularExpressionWithPattern:@"^(\\d{1,2})/(\\d{1,2})/(\\d{2,4}),\\s*(\\d{1,2})([.:])(\\d{2})$"
                                 options:0 error:nil];

        NSArray *patterns = @[ @"dd/MM/yy, HH.mm", @"dd/MM/yyyy, HH.mm",
                               @"dd/MM/yy, HH:mm", @"dd/MM/yyyy, HH:mm",
                               @"d/M/yy, H.mm",    @"d/M/yyyy, H.mm",
                               @"d/M/yy, H:mm",    @"d/M/yyyy, H:mm" ];
        NSLocale *posix = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        NSMutableArray *fs = [NSMutableArray array];
        for (NSString *p in patterns) {
            NSDateFormatter *f = [NSDateFormatter new];
            f.locale = posix;
            f.timeZone = [NSTimeZone localTimeZone];
            f.dateFormat = p;
            [fs addObject:f];
        }
        gFormatters = fs;

        Method m1 = class_getInstanceMethod([UILabel class], @selector(setText:));
        orig_setText = (void (*)(id, SEL, NSString *))method_getImplementation(m1);
        method_setImplementation(m1, (IMP)new_setText);

        Method m2 = class_getInstanceMethod([UILabel class], @selector(setAttributedText:));
        orig_setAttributedText = (void (*)(id, SEL, NSAttributedString *))method_getImplementation(m2);
        method_setImplementation(m2, (IMP)new_setAttributedText);

        // Kait utama: coba sekarang, dan setiap kali ada image baru dimuat (NA9 bisa dimuat belakangan).
        NA9TryHookMain();
        _dyld_register_func_for_add_image(NA9ImageAdded);
    }
}
