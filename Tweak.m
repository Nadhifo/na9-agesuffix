// NA9AgeSuffix v1.2.5
//
// 1) Menambahkan umur postingan di belakang tanggal upload NA9 TikTok:
//      22/10/26, 04.31  ->  22/10/26, 04.31 - 4h
//    Cara utama : mengait +[TTKHelperTools formattedDateTime:] (milik NA9TikTok.dylib), umur dihitung
//                 dari NSDate asli. Cadangan: mengait UILabel setText:/setAttributedText: dan menempelkan
//                 umur bila teksnya berbentuk tanggal.
//
// 2) Kartu kosong "(null)" di hasil pencarian (sisa slot iklan yang dikosongkan fitur "Remove ads" NA9):
//    - langsung disembunyikan, lalu
//    - ukurannya dinolkan di layout (hook sizeForItemAtIndex: pada section controllernya) supaya grid rapat kembali.
//      Bila daftar tidak bisa diakses, kartu tetap tersembunyi dan muncul SATU alert diagnosis (Copy).
//
// Murni Objective-C runtime, tidak butuh Substrate/ElleKit.
// Versi lengkap sebelumnya (timestamp feed, sembunyikan saran pencarian, dll) ada di archive/.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>

static NSRegularExpression *gRegex;
static NSArray<NSDateFormatter *> *gFormatters;
static BOOL gMainHooked = NO;

static NSString *(*orig_formattedDateTime)(id, SEL, NSDate *);
static void (*orig_setText)(id, SEL, NSString *);
static void (*orig_setAttributedText)(id, SEL, NSAttributedString *);

#pragma mark - Umur postingan

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

#pragma mark - Kartu "(null)"

// Kartu "(null)" (sisa slot iklan yang dikosongkan fitur "Remove ads" NA9) dibuat setinggi nol di layout:
// section controller pemiliknya ditandai, dan -sizeForItemAtIndex: untuk section itu mengembalikan tinggi 0,
// lalu layout diminta menghitung ulang. Hasilnya tidak ada ruang kosong di grid.
#define NA9_NULL_DIAG 1   // satu alert diagnosis HANYA bila kartu masih memakan ruang setelah dicoba

static const void *kNA9NullLabelKey = &kNA9NullLabelKey;  // dipasang di UILabel pemicu
static const void *kNA9HiddenByKey  = &kNA9HiddenByKey;   // dipasang di cell: label pemicu
static const void *kNA9SCKey        = &kNA9SCKey;         // dipasang di cell: section controller (weak)

@interface NA9WeakBox : NSObject
@property (nonatomic, weak) id obj;
@end
@implementation NA9WeakBox
@end

static NSHashTable *gNullSCs = nil;        // section controller yang menampung kartu "(null)" (pointer, weak)
static int gSizeHits = 0;                  // berapa kali ukuran nol dikembalikan (untuk diagnosis)
static int gSizeCalls = 0;                 // berapa kali hook ukuran dipanggil (untuk diagnosis)
static struct { Class cls; IMP orig; } gSizeTab[4];
static int gSizeCount = 0;

static UICollectionViewCell *NA9EnclosingCell(UIView *v) {
    UIView *p = v;
    for (int i = 0; i < 12 && p; i++, p = p.superview) {
        if ([p isKindOfClass:[UICollectionViewCell class]]) return (UICollectionViewCell *)p;
    }
    return nil;
}

static UICollectionView *NA9EnclosingCV(UIView *v) {
    UIView *p = v.superview;
    for (int i = 0; i < 6 && p; i++, p = p.superview) {
        if ([p isKindOfClass:[UICollectionView class]]) return (UICollectionView *)p;
    }
    return nil;
}

static NSString *NA9ClassChain(Class c) {
    NSMutableArray *parts = [NSMutableArray array];
    for (int i = 0; c && i < 8; i++, c = class_getSuperclass(c)) [parts addObject:NSStringFromClass(c)];
    return [parts componentsJoinedByString:@" < "];
}

static NSString *NA9RectStr(CGRect r) {
    return [NSString stringWithFormat:@"{{%.0f,%.0f},{%.0f,%.0f}}", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

#if NA9_NULL_DIAG
static BOOL gNullDiagShown = NO;

static NSString *NA9OwnMethods(Class c, NSArray<NSString *> *keys, int maxN) {
    unsigned int n = 0;
    Method *ms = class_copyMethodList(c, &n);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned int i = 0; i < n && (int)out.count < maxN; i++) {
        const char *sn = sel_getName(method_getName(ms[i]));
        BOOL ok = (keys.count == 0);
        for (NSString *k in keys) if (strcasestr(sn, k.UTF8String)) { ok = YES; break; }
        if (ok) [out addObject:[NSString stringWithUTF8String:sn]];
    }
    free(ms);
    return [out componentsJoinedByString:@" "];
}

static UIViewController *NA9TopVC(void) {
    UIWindow *win = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (w.isKeyWindow) win = w;
    }
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void NA9NullDiag(UICollectionView *cv, UIView *cell, id sc, NSString *why, NSString *log) {
    if (gNullDiagShown) return;
    UIViewController *top = NA9TopVC();
    if (!top || top.presentedViewController) return;
    gNullDiagShown = YES;
    NSArray *sizeKeys = @[@"size", @"height", @"width", @"column", @"attributes", @"prepare", @"item"];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"alasan: %@\n", why];
    [s appendFormat:@"cell: %@ frame=%@\n", cell ? NSStringFromClass([cell class]) : @"-", cell ? NA9RectStr(cell.frame) : @"-"];
    [s appendFormat:@"layout: %@\n", cv ? NA9ClassChain([cv.collectionViewLayout class]) : @"-"];
    [s appendFormat:@"layout methods: %@\n", cv ? NA9OwnMethods([cv.collectionViewLayout class], sizeKeys, 30) : @"-"];
    [s appendFormat:@"delegate: %@\n", cv.delegate ? NA9ClassChain([cv.delegate class]) : @"-"];
    if (sc) {
        [s appendFormat:@"sectionController: %@\n", NA9ClassChain([sc class])];
        [s appendFormat:@"sc methods: %@\n", NA9OwnMethods([sc class], sizeKeys, 30)];
    }
    [s appendFormat:@"hook ukuran: terpasang=%d dipanggil=%d dipanggil-nol=%d\n", gSizeCount, gSizeCalls, gSizeHits];
    if (log.length) { [s appendString:@"--- langkah ---\n"]; [s appendString:log]; }
    NSString *copy = [s copy];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"NA9: kartu (null) tidak bisa dirapikan"
                                                               message:copy
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) { [UIPasteboard generalPasteboard].string = copy; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}
#else
static void NA9NullDiag(UICollectionView *cv, UIView *cell, id sc, NSString *why, NSString *log) {}
#endif

// ---------- Hook ukuran: -[IGListSectionController sizeForItemAtIndex:] ----------
static IMP NA9SizeOrig(id self) {
    for (Class k = object_getClass(self); k; k = class_getSuperclass(k))
        for (int i = 0; i < gSizeCount; i++) if (gSizeTab[i].cls == k) return gSizeTab[i].orig;
    return NULL;
}

static CGSize new_sizeForItemAtIndex(id self, SEL _cmd, NSInteger index) {
    IMP o = NA9SizeOrig(self);
    CGSize s = CGSizeMake(0, 0);
    gSizeCalls++;
    if (o) s = ((CGSize (*)(id, SEL, NSInteger))o)(self, _cmd, index);
    if (gNullSCs.count && [gNullSCs containsObject:self]) {
        gSizeHits++;
        return CGSizeMake(s.width, 0);                 // lebar dipertahankan, tinggi nol
    }
    return s;
}

static BOOL NA9InstallSizeHook(Class c) {
    for (int i = 0; i < gSizeCount; i++) if (gSizeTab[i].cls == c) return YES;
    if (gSizeCount >= 4) return NO;
    SEL sel = NSSelectorFromString(@"sizeForItemAtIndex:");
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return NO;
    IMP inherited = class_getMethodImplementation(c, sel);
    const char *types = method_getTypeEncoding(m);
    IMP orig;
    if (class_addMethod(c, sel, (IMP)new_sizeForItemAtIndex, types)) orig = inherited;     // diwarisi
    else orig = method_setImplementation(class_getInstanceMethod(c, sel), (IMP)new_sizeForItemAtIndex);
    if (!orig) return NO;
    gSizeTab[gSizeCount].cls = c; gSizeTab[gSizeCount].orig = orig; gSizeCount++;
    return YES;
}

// IGListCollectionViewLayout hanya membuang cache ukurannya bila konteks invalidasi memuat index path item
// (invalidateLayout biasa tidak cukup). Konteks dibuat dengan item pemilik cell, lalu layout dipaksa hitung ulang.
static void NA9ForceRelayout(UICollectionView *cv, NSIndexPath *ip) {
    UICollectionViewLayout *layout = cv.collectionViewLayout;
    Class ctxClass = [[layout class] invalidationContextClass];
    UICollectionViewLayoutInvalidationContext *ctx = [[ctxClass alloc] init];
    [ctx invalidateItemsAtIndexPaths:@[ ip ?: [NSIndexPath indexPathForItem:0 inSection:0] ]];
    [layout invalidateLayoutWithContext:ctx];
    [cv setNeedsLayout];
}

// Tandai section controller pemilik cell ini (tinggi nol) lalu minta layout dihitung ulang.
static void NA9CollapseNullItem(UICollectionViewCell *cell) {
    NSMutableString *log = [NSMutableString string];
    UICollectionView *cv = NA9EnclosingCV(cell);
    if (!cv) { NA9NullDiag(nil, cell, nil, @"collection view tidak ditemukan", log); return; }

    SEL selSC  = NSSelectorFromString(@"sectionControllerForView:");
    SEL selNum = NSSelectorFromString(@"numberOfItems");
    id adapter = nil;
    if ([cv.dataSource respondsToSelector:selSC]) adapter = cv.dataSource;
    else if ([cv.delegate respondsToSelector:selSC]) adapter = cv.delegate;
    if (!adapter) { NA9NullDiag(cv, cell, nil, @"adapter IGListKit tidak ditemukan", log); return; }

    id sc = ((id (*)(id, SEL, id))objc_msgSend)(adapter, selSC, cell);
    if (!sc) { NA9NullDiag(cv, cell, nil, @"section controller tidak ditemukan", log); return; }
    [log appendFormat:@"adapter=%@ sc=%@\n", NSStringFromClass([adapter class]), NSStringFromClass([sc class])];
    [log appendFormat:@"frame sebelum=%@\n", NA9RectStr(cell.frame)];

    if ([sc respondsToSelector:selNum]) {
        long n = ((long (*)(id, SEL))objc_msgSend)(sc, selNum);
        [log appendFormat:@"numberOfItems=%ld\n", n];
        if (n > 1) { NA9NullDiag(cv, cell, sc, @"satu section berisi banyak item: tidak aman diciutkan", log); return; }
    }
    if (!NA9InstallSizeHook([sc class])) { NA9NullDiag(cv, cell, sc, @"section controller tidak punya sizeForItemAtIndex:", log); return; }

    if (!gNullSCs) gNullSCs = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
    [gNullSCs addObject:sc];
    NA9WeakBox *box = [NA9WeakBox new];
    box.obj = sc;
    objc_setAssociatedObject(cell, kNA9SCKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NA9ForceRelayout(cv, [cv indexPathForCell:cell]);

    __weak UICollectionViewCell *wcell = cell;
    __weak UICollectionView *wcv = cv;
    __weak id wsc = sc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UICollectionViewCell *c = wcell;
        if (c && c.window && objc_getAssociatedObject(c, kNA9HiddenByKey) && c.frame.size.height > 2) {
            [log appendFormat:@"frame sesudah=%@\n", NA9RectStr(c.frame)];
            NA9NullDiag(wcv, c, wsc, @"kartu masih memakan ruang setelah ukuran dinolkan", log);
        }
    });
}

// text == persis "(null)"  -> sembunyikan cell pembungkus label ini, lalu ciutkan ruangnya.
// label yang sama berganti ke teks lain (cell dipakai ulang) -> tampilkan lagi dan kembalikan ukuran.
static void NA9HideNullCell(UILabel *label, NSString *text) {
    if (![label isKindOfClass:[UILabel class]]) return;
    BOOL isNull = [text isKindOfClass:[NSString class]] && [text isEqualToString:@"(null)"];
    if (isNull) {
        UICollectionViewCell *cell = NA9EnclosingCell(label);
        if (!cell) return;
        BOOL first = (objc_getAssociatedObject(cell, kNA9HiddenByKey) == nil);
        objc_setAssociatedObject(label, kNA9NullLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell, kNA9HiddenByKey,
                                 [NSValue valueWithPointer:(__bridge const void *)label],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.hidden = YES;
        cell.userInteractionEnabled = NO;
        if (first) {
            __weak UICollectionViewCell *wcell = cell;
            // Ditunda: jangan mengubah layout saat cell sedang dikonfigurasi.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UICollectionViewCell *c = wcell;
                if (c && c.hidden) NA9CollapseNullItem(c);
            });
        }
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
            NA9WeakBox *box = objc_getAssociatedObject(cell, kNA9SCKey);
            id sc = box.obj;
            if (sc) {                                           // kembalikan ukuran normal section ini
                [gNullSCs removeObject:sc];
                UICollectionView *cv = NA9EnclosingCV(cell);
                if (cv) NA9ForceRelayout(cv, [cv indexPathForCell:cell]);
            }
            objc_setAssociatedObject(cell, kNA9SCKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

#pragma mark - Kait UILabel

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

        gNullSCs = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];

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
