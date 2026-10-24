// NA9AgeSuffix v1.9
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

// ---------- Pembantu bersama (selalu dikompilasi) ----------
static int gNodeBudget = 0;                    // batas jumlah view yang diperiksa per putaran
static NSMutableString *gPatchReport = nil;    // laporan penambalan timestamp (dibaca discovery)
static BOOL gPatchRan = NO;
static BOOL NA9IsTarget(NSString *t) {
    NSString *l = t.lowercaseString;
    return [l containsString:@"you may like"] || [l containsString:@"trending search"];
}

static NSArray<UIWindow *> *NA9AllWindows(void) {
    NSMutableArray *ws = [NSMutableArray array];
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        [ws addObjectsFromArray:((UIWindowScene *)sc).windows];
    }
    return ws;
}

static NSString *NA9QuickText(UIView *v) {
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        return l.text ?: l.attributedText.string;
    }
    NSString *names[2] = { @"text", @"attributedText" };
    for (int i = 0; i < 2; i++) {
        SEL sel = NSSelectorFromString(names[i]);
        if (![v respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [v methodSignatureForSelector:sel];
        if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id r = [v performSelector:sel];
#pragma clang diagnostic pop
        if ([r isKindOfClass:[NSString class]]) return r;
        if ([r isKindOfClass:[NSAttributedString class]]) return [(NSAttributedString *)r string];
    }
    return nil;
}

// Iterasi nama semua class ObjC di image milik aplikasi (path dari dyld, tanpa merealisasi class).
static void NA9ForEachAppClass(void (^cb)(const char *name)) {
    uint32_t cnt = _dyld_image_count();
    for (uint32_t i = 0; i < cnt; i++) {
        const char *p = _dyld_get_image_name(i);
        if (!p || !strstr(p, ".app/")) continue;
        unsigned int n = 0;
        const char **names = objc_copyClassNamesForImage(p, &n);
        if (!names) continue;
        for (unsigned int j = 0; j < n; j++) cb(names[j]);
        free(names);
    }
}

static UIViewController *NA9TopVC(void) {
    UIWindow *win = nil;
    for (UIWindow *w in NA9AllWindows()) if (w.isKeyWindow) win = w;
    UIViewController *top = win.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static NSString *NA9Chain(UIView *v) {
    NSMutableArray *parts = [NSMutableArray array];
    UIView *p = v;
    for (int i = 0; p && i < 14; i++, p = p.superview) [parts addObject:NSStringFromClass([p class])];
    return [parts componentsJoinedByString:@" < "];
}

static NSString *NA9Describe(UIView *l) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"views: %@\n", NA9Chain(l)];
    UIView *cell = nil, *p = l;
    UITableView *tv = nil; UICollectionView *cv = nil;
    while (p) {
        if (!cell && ([p isKindOfClass:[UITableViewCell class]] ||
                      [p isKindOfClass:[UITableViewHeaderFooterView class]] ||
                      [p isKindOfClass:[UICollectionReusableView class]])) cell = p;
        if ([p isKindOfClass:[UITableView class]]) { tv = (UITableView *)p; break; }
        if ([p isKindOfClass:[UICollectionView class]]) { cv = (UICollectionView *)p; break; }
        p = p.superview;
    }
    if (cell) [s appendFormat:@"cell: %@\n", NSStringFromClass([cell class])];
    if (tv) [s appendFormat:@"table: %@ ds=%@ delegate=%@\n", NSStringFromClass([tv class]),
             NSStringFromClass([tv.dataSource class]), NSStringFromClass([tv.delegate class])];
    if (cv) [s appendFormat:@"collection: %@ layout=%@ ds=%@ delegate=%@\n", NSStringFromClass([cv class]),
             NSStringFromClass([cv.collectionViewLayout class]),
             NSStringFromClass([cv.dataSource class]), NSStringFromClass([cv.delegate class])];
    NSMutableArray *vcs = [NSMutableArray array];
    UIResponder *r = l;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
    UIViewController *vc = (UIViewController *)r;
    while (vc) { [vcs addObject:NSStringFromClass([vc class])]; vc = vc.parentViewController; }
    [s appendFormat:@"controllers: %@\n", [vcs componentsJoinedByString:@" < "]];
    return s;
}

static void NA9PresentAlert(NSString *title, NSString *msg, BOOL withCopy) {
    UIViewController *top = NA9TopVC();
    if (!top || top.presentedViewController) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    if (withCopy)
        [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) { [UIPasteboard generalPasteboard].string = msg; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

static BOOL NA9LabelIsTarget(UIView *v) {
    NSString *t = nil;
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        t = l.text ?: l.attributedText.string;
    } else {
        const char *cn = class_getName(object_getClass(v));
        if (!cn || !(strstr(cn, "Label") || strstr(cn, "Text"))) return NO;
        t = NA9QuickText(v);
    }
    return t.length > 0 && NA9IsTarget(t);
}

// ---------- Sembunyikan "You may like" & "Trending searches" ----------
// Mencari UILabel dengan teks tsb, lalu menyembunyikan daftar (table/collection/scroll view) yang
// membungkusnya, sehingga halaman pencarian kosong seperti di RX. Daftar ditampilkan lagi bila
// isinya berganti (mis. saat mengetik) atau halamannya ditutup.
// Teks yang dikenali: bahasa Inggris. Set ke 0 untuk mematikan.
#define NA9_HIDE_SEARCH_SUGGESTIONS 1
#if NA9_HIDE_SEARCH_SUGGESTIONS
static __weak UIView *gSugList = nil;
static BOOL gSugDiagShown = NO;

static UIView *NA9FindTargetLabel(UIView *v, int depth) {
    if (depth > 70 || gNodeBudget-- <= 0 || v.hidden || v.alpha < 0.01) return nil;
    if (NA9LabelIsTarget(v)) return v;
    for (UIView *sv in v.subviews) {
        UIView *r = NA9FindTargetLabel(sv, depth + 1);
        if (r) return r;
    }
    return nil;
}

static BOOL NA9ContainsTarget(UIView *v, int depth) {          // tanpa memeriksa hidden
    if (depth > 70 || gNodeBudget-- <= 0) return NO;
    if (NA9LabelIsTarget(v)) return YES;
    for (UIView *sv in v.subviews) if (NA9ContainsTarget(sv, depth + 1)) return YES;
    return NO;
}

static UIView *NA9ListFor(UIView *label) {
    UIView *p = label.superview, *scroll = nil;
    while (p) {
        if ([p isKindOfClass:[UITableView class]] || [p isKindOfClass:[UICollectionView class]]) return p;
        if (!scroll && [p isKindOfClass:[UIScrollView class]]) scroll = p;
        p = p.superview;
    }
    return scroll;
}

static void NA9HideTick(void) {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    gNodeBudget = 6000;
    UIView *list = gSugList;
    if (list) {
        if (list.window && NA9ContainsTarget(list, 0)) { if (!list.hidden) list.hidden = YES; return; }
        list.hidden = NO;                                         // isi berganti / halaman ditutup
        gSugList = nil;
    }
    gNodeBudget = 6000;
    UIView *hit = nil;
    for (UIWindow *w in NA9AllWindows()) { hit = NA9FindTargetLabel(w, 0); if (hit) break; }
    if (!hit) return;
    UIView *container = NA9ListFor(hit);
    if (container) {
        container.hidden = YES;
        gSugList = container;
    } else if (!gSugDiagShown && NA9TopVC() && !NA9TopVC().presentedViewController) {
        gSugDiagShown = YES;
        NA9PresentAlert(@"NA9: daftar tidak ditemukan",
                        [NSString stringWithFormat:@"\"%@\"\n%@", NA9QuickText(hit), NA9Describe(hit)], YES);
    }
}
#else
static void NA9HideTick(void) {}
#endif

// ---------- PROBE (opsional, untuk diagnosis) ----------
// Set NA9_PROBE ke 1 bila perlu: alert "NA9 Probe aktif" ~5 dtk setelah TikTok dibuka, lalu alert
// berisi rantai view untuk teks target (UILabel, view dengan -text/-attributedText, accessibilityLabel).
#define NA9_PROBE 0
#if NA9_PROBE
static BOOL gProbeDone = NO, gHelloDone = NO;
static NSDate *gProbeStart = nil;

static NSString *NA9TextOf(UIView *v, NSString **via) {
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        NSString *t = l.text ?: l.attributedText.string;
        if (t.length) { *via = @"UILabel"; return t; }
    }
    NSString *names[2] = { @"text", @"attributedText" };
    for (int i = 0; i < 2; i++) {
        SEL sel = NSSelectorFromString(names[i]);
        if (![v respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [v methodSignatureForSelector:sel];
        if (!sig || sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id r = [v performSelector:sel];
#pragma clang diagnostic pop
        if ([r isKindOfClass:[NSString class]] && [r length]) { *via = [@"-" stringByAppendingString:names[i]]; return r; }
        if ([r isKindOfClass:[NSAttributedString class]] && [r length]) { *via = [@"-" stringByAppendingString:names[i]]; return [(NSAttributedString *)r string]; }
    }
    NSString *ax = v.accessibilityLabel;
    if (ax.length) { *via = @"accessibilityLabel"; return ax; }
    return nil;
}

static void NA9Scan(UIView *v, NSMutableArray<UIView *> *hits, NSMutableArray<NSString *> *vias, int depth) {
    if (depth > 70 || hits.count >= 4 || v.hidden || v.alpha < 0.01) return;
    NSString *via = nil, *t = NA9TextOf(v, &via);
    if (t && NA9IsTarget(t)) {
        [hits addObject:v];
        [vias addObject:[NSString stringWithFormat:@"%@ \"%@\" [%@]", via, t, NSStringFromClass([v class])]];
    }
    for (UIView *sv in v.subviews) NA9Scan(sv, hits, vias, depth + 1);
}

static void NA9ProbeTick(void) {
    if (!gProbeStart) gProbeStart = [NSDate date];
    if (!gHelloDone) {
        if ([[NSDate date] timeIntervalSinceDate:gProbeStart] > 5 && NA9TopVC() && !NA9TopVC().presentedViewController) {
            gHelloDone = YES;
            NA9PresentAlert(@"NA9 Probe aktif", @"Dylib versi probe termuat. Buka halaman pencarian dan tunggu beberapa detik.", NO);
        }
        return;
    }
    if (gProbeDone) return;
    NSMutableArray *hits = [NSMutableArray array], *vias = [NSMutableArray array];
    for (UIWindow *w in NA9AllWindows()) NA9Scan(w, hits, vias, 0);
    if (hits.count == 0 || !NA9TopVC() || NA9TopVC().presentedViewController) return;
    NSMutableString *msg = [NSMutableString string];
    for (NSUInteger i = 0; i < hits.count; i++)
        [msg appendFormat:@"%@\n%@\n", vias[i], NA9Describe(hits[i])];
    gProbeDone = YES;
    NA9PresentAlert(@"NA9 Probe", msg, YES);
}
#else
static void NA9ProbeTick(void) {}
#endif


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

// ---------- Tanggal upload di samping nama akun (fitur bawaan TikTok) ----------
// TikTok punya label waktu di samping nama akun di feed ("· 13h ago", "· 9-26") yang dikontrol
// -shouldShowTimeStampLabel. Di sini method itu dipaksa mengembalikan YES (nama class tidak perlu
// diketahui: semua class di dalam .app yang punya method itu ditambal, instance maupun class method).
#define NA9_FEED_TIMESTAMPS 1
#if NA9_FEED_TIMESTAMPS
static BOOL na9_yes(id self, SEL _cmd) { return YES; }

// Hanya class di executable utama yang namanya berkaitan dengan tampilan feed/penulis/waktu yang diperiksa,
// dan paling banyak 8000 class (memindai SEMUA class memaksa runtime merealisasi puluhan ribu class).
static BOOL NA9NameLooksRelevant(const char *nm) {
    static const char *keys[] = { "TimeStamp", "Timestamp", "Author", "UserName", "Nickname",
                                  "Interaction", "Description", "FeedCell", "PostTime", "CreateTime",
                                  "AWEFeed", "AWEPlay", "TTKFeed", "TTKPlay", "Aweme", "FYP", "Time" };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++)
        if (strcasestr(nm, keys[i])) return YES;
    return NO;
}

static void NA9PatchTimestampFlag(void) {
    SEL sel = NSSelectorFromString(@"shouldShowTimeStampLabel");
    __block unsigned int total = 0, scanned = 0, patched = 0;
    NSMutableString *rep = [NSMutableString string];
    NA9ForEachAppClass(^(const char *name) {
        total++;
        if (scanned >= 8000 || !NA9NameLooksRelevant(name)) return;
        scanned++;
        Class c = objc_getClass(name);
        if (!c) return;
        for (int pass = 0; pass < 2; pass++) {
            Class k = pass ? object_getClass(c) : c;                  // pass 1 = class method
            Method m = class_getInstanceMethod(k, sel);
            if (!m) continue;
            [rep appendFormat:@"  found %s%s\n", pass ? "+" : "-", name];
            Class sup = class_getSuperclass(k);
            if (sup && class_getInstanceMethod(sup, sel) == m) continue;   // warisan, bukan milik k
            if (method_getNumberOfArguments(m) != 2) continue;
            char *rt = method_copyReturnType(m);
            BOOL boolish = rt && (rt[0] == 'B' || rt[0] == 'c');
            free(rt);
            if (!boolish || method_getImplementation(m) == (IMP)na9_yes) continue;
            method_setImplementation(m, (IMP)na9_yes);
            patched++;
            [rep appendFormat:@"  PATCHED %s%s\n", pass ? "+" : "-", name];
        }
    });
    @synchronized ([NSProcessInfo class]) {
        gPatchReport = [NSMutableString stringWithFormat:@"timestamp: %u kandidat diperiksa dari %u class, %u ditambal\n%@", scanned, total, patched, rep];
        gPatchRan = YES;
    }
}

static void NA9StartTimestampPatch(void) {
    // Ditunda supaya tidak memperlambat peluncuran; diulang sekali untuk class yang dimuat belakangan.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ NA9PatchTimestampFlag(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ NA9PatchTimestampFlag(); });
}
#else
static void NA9StartTimestampPatch(void) {}
#endif

// ---------- Sembunyikan view TikTok berdasarkan nama class ----------
// Hide Play/Pause Button  : ikon jeda di tengah video  (AWEAwemePlayVideoPauseIcon, TTKMediaDefaultPauseIconView)
// Disable Visual Search Tag: tag/titik "visual search" di video (TTKVisualSearchTagView, TTKVisualSearchEntityDotView)
// Cara kerja: setHidden: pada class itu dipaksa selalu YES, dan didMoveToWindow menyembunyikannya langsung.
// Nama class berasal dari discovery; bila salah satu tidak ada di versi TikTok-mu, dilewati diam-diam.
#define NA9_HIDE_PLAYPAUSE 1
#define NA9_HIDE_VISUALSEARCH 1
typedef void (*NA9VoidIMP)(id, SEL);
typedef void (*NA9BoolIMP)(id, SEL, BOOL);
static struct { Class cls; IMP origHidden; IMP origWin; } gHideTab[8];
static int gHideCount = 0;

static IMP NA9HideOrig(id self, BOOL forHidden) {
    for (Class k = object_getClass(self); k; k = class_getSuperclass(k))
        for (int i = 0; i < gHideCount; i++)
            if (gHideTab[i].cls == k) return forHidden ? gHideTab[i].origHidden : gHideTab[i].origWin;
    return NULL;
}

static void na9_hide_setHidden(id self, SEL _cmd, BOOL hidden) {
    NA9BoolIMP o = (NA9BoolIMP)NA9HideOrig(self, YES);
    if (o) o(self, _cmd, YES);                       // apa pun yang diminta TikTok, tetap tersembunyi
}

static void na9_hide_didMoveToWindow(id self, SEL _cmd) {
    NA9VoidIMP o = (NA9VoidIMP)NA9HideOrig(self, NO);
    if (o) o(self, _cmd);
    [(UIView *)self setHidden:YES];
}

static IMP NA9InstallOverride(Class c, SEL sel, IMP newImp, const char *fallbackTypes) {
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return NULL;
    IMP inherited = class_getMethodImplementation(c, sel);
    const char *types = method_getTypeEncoding(m) ?: fallbackTypes;
    if (class_addMethod(c, sel, newImp, types)) return inherited;          // class belum punya sendiri
    return method_setImplementation(class_getInstanceMethod(c, sel), newImp);   // class punya sendiri
}

static void NA9HookHideClass(const char *name) {
    Class c = objc_getClass(name);
    if (!c || ![c isSubclassOfClass:[UIView class]] || gHideCount >= 8) return;
    for (int i = 0; i < gHideCount; i++) if (gHideTab[i].cls == c) return;     // sudah
    IMP oh = NA9InstallOverride(c, @selector(setHidden:), (IMP)na9_hide_setHidden, "v20@0:8B16");
    IMP ow = NA9InstallOverride(c, @selector(didMoveToWindow), (IMP)na9_hide_didMoveToWindow, "v16@0:8");
    if (!oh || !ow) return;
    gHideTab[gHideCount].cls = c; gHideTab[gHideCount].origHidden = oh; gHideTab[gHideCount].origWin = ow;
    gHideCount++;
    NSLog(@"[NA9AgeSuffix] hide class: %s", name);
}

static void NA9InstallHideClasses(void) {
#if NA9_HIDE_PLAYPAUSE
    NA9HookHideClass("AWEAwemePlayVideoPauseIcon");
    NA9HookHideClass("TTKMediaDefaultPauseIconView");
#endif
#if NA9_HIDE_VISUALSEARCH
    NA9HookHideClass("TTKVisualSearchTagView");
    NA9HookHideClass("TTKVisualSearchEntityDotView");
#endif
}

static void NA9StartHideClasses(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NA9InstallHideClasses(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NA9InstallHideClasses(); });
}

// ---------- DISCOVERY (v1.7): kumpulkan nama class untuk fitur yang akan dibuat ----------
// Alert A (~9 dtk setelah TikTok dibuka): nama class yang cocok dengan kata kunci tiap fitur + laporan timestamp.
// Alert B (sekitar 1.5 dtk setelah halaman pencarian terbuka): rantai view/controller kolom pencarian dan
// pohon view halamannya. Keduanya punya tombol Copy. Set NA9_DISCOVERY ke 0 bila sudah tidak perlu.
#define NA9_DISCOVERY 1
#if NA9_DISCOVERY
static BOOL gDiscAShown = NO, gDiscBShown = NO;
static NSDate *gDiscStart = nil, *gSearchSeenAt = nil;

static void NA9DumpTree(UIView *v, int depth, NSMutableString *out, int *lines) {
    if (*lines >= 260 || depth > 14 || v.hidden || v.alpha < 0.01) return;
    NSString *t = NA9QuickText(v);
    if (t.length > 40) t = [t substringToIndex:40];
    [out appendFormat:@"%*s%@%@\n", depth * 2, "", NSStringFromClass([v class]),
        t.length ? [NSString stringWithFormat:@" \"%@\"", t] : @""];
    (*lines)++;
    NSString *lastCls = nil; int same = 0, skipped = 0;
    for (UIView *sv in v.subviews) {
        NSString *cn = NSStringFromClass([sv class]);
        if ([cn isEqualToString:lastCls]) { same++; if (same >= 3) { skipped++; continue; } }
        else { if (skipped) { [out appendFormat:@"%*s... +%d %@ lain\n", (depth + 1) * 2, "", skipped, lastCls]; skipped = 0; } lastCls = cn; same = 0; }
        NA9DumpTree(sv, depth + 1, out, lines);
    }
    if (skipped) [out appendFormat:@"%*s... +%d %@ lain\n", (depth + 1) * 2, "", skipped, lastCls];
}

// Kolom pencarian KOSONG milik AWESearchBar (= halaman awal pencarian: riwayat / You may like / Trending).
static UITextField *NA9FindSearchField(UIView *v, int depth) {
    if (depth > 70 || gNodeBudget-- <= 0 || v.hidden || v.alpha < 0.01) return nil;
    if ([v isKindOfClass:[UITextField class]] && ((UITextField *)v).text.length == 0) {
        UIView *p = v.superview;
        for (int i = 0; p && i < 8; i++, p = p.superview) {
            const char *cn = class_getName(object_getClass(p));
            if (cn && strstr(cn, "SearchBar")) return (UITextField *)v;
        }
    }
    for (UIView *sv in v.subviews) {
        UITextField *r = NA9FindSearchField(sv, depth + 1);
        if (r) return r;
    }
    return nil;
}

static void NA9DiscoveryA(void) {
    NSArray *groups = @[
        @[@"timestamp",    @"TimeStamp", @"Timestamp"],
        @[@"visualsearch", @"VisualSearch"],
        @[@"playpause",    @"PlayPause", @"PauseIcon", @"PlayIcon", @"PauseButton", @"PlayButton"],
        @[@"followlist",   @"FollowerList", @"FollowingList", @"FollowList", @"FansList", @"RelationList"],
        @[@"story",        @"StoryView", @"StoryPlayer", @"StorySeen", @"StoryRing", @"StoryTray"],
        @[@"search",       @"SearchSug", @"HotSearch", @"Trending", @"YouMayLike", @"GuessYouLike", @"SearchHome", @"SearchRecommend", @"SearchHistory"],
    ];
    NSMutableArray<NSMutableArray<NSString *> *> *hits = [NSMutableArray array];
    for (NSUInteger i = 0; i < groups.count; i++) [hits addObject:[NSMutableArray array]];
    __block unsigned int total = 0;
    NA9ForEachAppClass(^(const char *name) {
        total++;
        for (NSUInteger gi = 0; gi < groups.count; gi++) {
            NSArray *g = groups[gi];
            for (NSUInteger k = 1; k < g.count; k++) {
                if (strcasestr(name, [g[k] UTF8String])) {
                    if (hits[gi].count < 400) [hits[gi] addObject:[NSString stringWithUTF8String:name]];
                    break;
                }
            }
        }
    });
    NSMutableString *out = [NSMutableString stringWithFormat:@"NA9 discovery A (kelas di app: %u)\n", total];
    for (NSUInteger gi = 0; gi < groups.count; gi++) {
        NSMutableArray<NSString *> *h = hits[gi];
        [h sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return a.length < b.length ? NSOrderedAscending : (a.length > b.length ? NSOrderedDescending : NSOrderedSame);
        }];
        [out appendFormat:@"[%@] %lu cocok\n", groups[gi][0], (unsigned long)h.count];
        for (NSUInteger i = 0; i < h.count && i < 12; i++) [out appendFormat:@"  %@\n", h[i]];
    }
    @synchronized ([NSProcessInfo class]) { if (gPatchReport) [out appendString:gPatchReport]; }
    NA9PresentAlert(@"NA9 Discovery A", out, YES);
}

static void NA9DiscoveryB(UITextField *tf) {
    NSMutableString *out = [NSMutableString stringWithString:@"NA9 discovery B (halaman awal pencarian)\n"];
    [out appendFormat:@"field: %@ placeholder=%@\n", NSStringFromClass([tf class]), tf.placeholder ?: tf.attributedPlaceholder.string];
    [out appendString:NA9Describe(tf)];
    UIResponder *r = tf;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
    UIView *root = [(UIViewController *)r view] ?: tf.window;
    int lines = 0;
    [out appendString:@"--- pohon view ---\n"];
    NA9DumpTree(root, 0, out, &lines);
    NA9PresentAlert(@"NA9 Discovery B", out, YES);
}


static NSString *NA9MatchedSelectors(Class k, const char *prefix, NSArray<NSString *> *keys, int maxN) {
    unsigned int mc = 0;
    Method *ms = class_copyMethodList(k, &mc);
    NSMutableArray *hit = [NSMutableArray array];
    for (unsigned int i = 0; i < mc && (int)hit.count < maxN; i++) {
        const char *sn = sel_getName(method_getName(ms[i]));
        for (NSString *key in keys) {
            if (strcasestr(sn, key.UTF8String)) { [hit addObject:[NSString stringWithFormat:@"%s%s", prefix, sn]]; break; }
        }
    }
    free(ms);
    return [hit componentsJoinedByString:@" "];
}

static BOOL gDiscCShown = NO;
static void NA9DiscoveryC(void) {
    NSArray *storyKeys  = @[@"report", @"seen", @"viewed", @"unread", @"watched", @"mark"];
    NSArray *followKeys = @[@"limit", @"truncat", @"search", @"max", @"canShow"];
    NSArray *exact = @[@"reportStoryViewedWithStoryID:uid:completion:",
                       @"reportStoryViewedWithStoryID:uid:unlocked:completion:",
                       @"showFollowerTruncationNoticeInOtherFollowerList",
                       @"searchEnable", @"setSearchEnable:",
                       @"p_enableNewSearchBarForSelf", @"p_enableNewSearchBarForOther"];
    NSMutableString *story = [NSMutableString string], *follow = [NSMutableString string], *impl = [NSMutableString string];
    __block int cand = 0, sl = 0, fl = 0;
    NA9ForEachAppClass(^(const char *name) {
        BOOL isStory = strcasestr(name, "Story") != NULL;
        BOOL isFollow = strcasestr(name, "Follow") || strcasestr(name, "Relation") || strcasestr(name, "FansList");
        if ((!isStory && !isFollow) || cand >= 1500) return;
        cand++;
        Class c = objc_getClass(name);
        if (!c) return;
        for (int pass = 0; pass < 2; pass++) {
            Class k = pass ? object_getClass(c) : c;
            for (NSString *e in exact) {
                Method m = class_getInstanceMethod(k, NSSelectorFromString(e));
                if (!m) continue;
                Class sup = class_getSuperclass(k);
                if (sup && class_getInstanceMethod(sup, NSSelectorFromString(e)) == m) continue;
                char *rt = method_copyReturnType(m);
                [impl appendFormat:@"%s%s  %@  ret=%s\n", pass ? "+" : "-", name, e, rt ?: "?"];
                free(rt);
            }
        }
        NSArray *keys = isStory ? storyKeys : followKeys;
        NSString *a = NA9MatchedSelectors(c, "-", keys, 6), *b = NA9MatchedSelectors(object_getClass(c), "+", keys, 4);
        NSString *line = [[a stringByAppendingFormat:@" %@", b] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length == 0) return;
        if (isStory && sl < 70) { sl++; [story appendFormat:@"%s: %@\n", name, line]; }
        else if (isFollow && !isStory && fl < 70) { fl++; [follow appendFormat:@"%s: %@\n", name, line]; }
    });
    NSMutableString *out = [NSMutableString stringWithFormat:@"NA9 discovery C (%d class diperiksa)\n--- pelaksana selector RX ---\n%@--- story ---\n%@--- follow/relation ---\n%@", cand, impl, story, follow];
    NA9PresentAlert(@"NA9 Discovery C", out, YES);
}

static void NA9DiscoveryTick(void) {
    if (!gDiscStart) gDiscStart = [NSDate date];
    if (gDiscCShown || !gPatchRan) return;
    if ([[NSDate date] timeIntervalSinceDate:gDiscStart] < 8) return;
    if (!(NA9TopVC() && !NA9TopVC().presentedViewController)) return;
    gDiscCShown = YES;
    NA9DiscoveryC();
}
#else
static void NA9DiscoveryTick(void) {}
#endif

static void NA9TimerStart(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *t) {
            NA9HideTick();
            NA9ProbeTick();
            NA9DiscoveryTick();
        }];
    });
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
        NA9TimerStart();
        NA9StartTimestampPatch();
        NA9StartHideClasses();
    }
}
