// NA9AgeSuffix v1.6a
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
    if (![v isKindOfClass:[UILabel class]]) return NO;
    UILabel *l = (UILabel *)v;
    NSString *t = l.text ?: l.attributedText.string;
    return t.length > 0 && NA9IsTarget(t);
}

// ---------- Sembunyikan "You may like" & "Trending searches" ----------
// v1.7: dukung lebih dari satu daftar dan pulihkan saat pengguna mulai mengetik.
// Catatan: container yang disembunyikan adalah table/collection/scroll view terdekat.
#define NA9_HIDE_SEARCH_SUGGESTIONS 1
#if NA9_HIDE_SEARCH_SUGGESTIONS
static NSHashTable<UIView *> *gSugLists = nil; // weak references; dapat ada >1 container
static BOOL gSugDiagShown = NO;
static int gNodeBudget = 0;
static const void *kNA9SugOriginalHiddenKey = &kNA9SugOriginalHiddenKey;

static UILabel *NA9FindTargetLabel(UIView *v, int depth) {
    if (!v || depth > 70 || gNodeBudget-- <= 0 || v.hidden || v.alpha < 0.01) return nil;
    if (NA9LabelIsTarget(v) && !objc_getAssociatedObject(v, @selector(NA9HideTick))) return (UILabel *)v;
    for (UIView *sv in v.subviews) {
        UILabel *r = NA9FindTargetLabel(sv, depth + 1);
        if (r) return r;
    }
    return nil;
}

static BOOL NA9ContainsTarget(UIView *v, int depth) {
    if (!v || depth > 70 || gNodeBudget-- <= 0) return NO;
    if (NA9LabelIsTarget(v)) return YES;
    for (UIView *sv in v.subviews) {
        if (NA9ContainsTarget(sv, depth + 1)) return YES;
    }
    return NO;
}

static UIView *NA9ListFor(UIView *label) {
    UIView *p = label.superview, *scroll = nil;
    while (p) {
        if ([p isKindOfClass:[UITableView class]] ||
            [p isKindOfClass:[UICollectionView class]]) return p;
        if (!scroll && [p isKindOfClass:[UIScrollView class]]) scroll = p;
        p = p.superview;
    }
    return scroll;
}

// Deteksi kolom pencarian yang sudah berisi teks. Saat mulai mengetik, pulihkan
// daftar yang disembunyikan agar hasil pencarian tetap dapat tampil.
static BOOL NA9SearchHasQueryInView(UIView *v, int depth) {
    if (!v || depth > 70 || gNodeBudget-- <= 0) return NO;
    if ([v isKindOfClass:[UISearchBar class]]) {
        NSString *t = ((UISearchBar *)v).text;
        if ([t isKindOfClass:[NSString class]] &&
            [[t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0)
            return YES;
    }
    if ([v isKindOfClass:[UITextField class]]) {
        NSString *t = ((UITextField *)v).text;
        if ([t isKindOfClass:[NSString class]] &&
            [[t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0)
            return YES;
    }
    for (UIView *sv in v.subviews) {
        if (NA9SearchHasQueryInView(sv, depth + 1)) return YES;
    }
    return NO;
}

static void NA9RestoreSugLists(void) {
    for (UIView *v in gSugLists.allObjects) {
        NSNumber *wasHidden = objc_getAssociatedObject(v, kNA9SugOriginalHiddenKey);
        if (wasHidden) {
            v.hidden = wasHidden.boolValue;
            objc_setAssociatedObject(v, kNA9SugOriginalHiddenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    [gSugLists removeAllObjects];
}

static void NA9HideSugList(UIView *v) {
    if (!v) return;
    if (!gSugLists) gSugLists = [NSHashTable weakObjectsHashTable];
    if (!objc_getAssociatedObject(v, kNA9SugOriginalHiddenKey)) {
        objc_setAssociatedObject(v, kNA9SugOriginalHiddenKey, @(v.hidden),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gSugLists addObject:v];
    }
    v.hidden = YES;
}

static void NA9HideTick(void) {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (!gSugLists) gSugLists = [NSHashTable weakObjectsHashTable];

    // Jangan menutup daftar saat pengguna sudah mengetik; hasil pencarian perlu terlihat.
    gNodeBudget = 12000;
    BOOL hasQuery = NO;
    for (UIWindow *w in NA9AllWindows()) {
        if (NA9SearchHasQueryInView(w, 0)) { hasQuery = YES; break; }
    }
    if (hasQuery) {
        NA9RestoreSugLists();
        return;
    }

    // Pulihkan container yang sudah tidak memuat label target (mis. halaman Search ditutup
    // atau UI berubah), pertahankan yang masih memuat target meskipun sedang hidden.
    for (UIView *v in gSugLists.allObjects) {
        gNodeBudget = 6000;
        if (!v.window || !NA9ContainsTarget(v, 0)) {
            NSNumber *wasHidden = objc_getAssociatedObject(v, kNA9SugOriginalHiddenKey);
            if (wasHidden) v.hidden = wasHidden.boolValue;
            objc_setAssociatedObject(v, kNA9SugOriginalHiddenKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [gSugLists removeObject:v];
        } else {
            v.hidden = YES;
        }
    }

    // Bersihkan penanda pencarian sementara agar label yang dipakai ulang dapat terdeteksi lagi.
    for (UIWindow *w in NA9AllWindows()) {
        gNodeBudget = 12000;
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count && gNodeBudget-- > 0) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            objc_setAssociatedObject(v, @selector(NA9HideTick), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [stack addObjectsFromArray:v.subviews];
        }
    }

    // Cari kedua judul di seluruh window, bukan hanya label pertama yang ditemukan.
    for (UIWindow *w in NA9AllWindows()) {
        for (NSUInteger pass = 0; pass < 2; pass++) {
            gNodeBudget = 6000;
            UILabel *hit = NA9FindTargetLabel(w, 0);
            if (!hit) break;
            UIView *container = NA9ListFor(hit);
            if (container) {
                NA9HideSugList(container);
                // Tandai label agar pencarian berikutnya di window ini tidak berulang pada
                // container yang sama; label tidak diubah sehingga teks UI tetap asli.
                objc_setAssociatedObject(hit, @selector(NA9HideTick), @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                // Lanjutkan pencarian untuk menemukan judul kedua jika berada di container lain.
            } else if (!gSugDiagShown && NA9TopVC() && !NA9TopVC().presentedViewController) {
                gSugDiagShown = YES;
                NA9PresentAlert(@"NA9: daftar tidak ditemukan",
                                [NSString stringWithFormat:@"%@\n%@", hit.text ?: @"", NA9Describe(hit)], YES);
                break;
            } else {
                break;
            }
        }
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

static void NA9TimerStart(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *t) {
            NA9HideTick();
            NA9ProbeTick();
        }];
    });
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

// ---------- Tanggal upload di samping nama akun (fitur bawaan TikTok) ----------
// TikTok punya label waktu di samping nama akun di feed ("· 13h ago", "· 9-26") yang dikontrol
// -shouldShowTimeStampLabel. Di sini method itu dipaksa mengembalikan YES (nama class tidak perlu
// diketahui: semua class di dalam .app yang punya method itu ditambal, instance maupun class method).
#define NA9_FEED_TIMESTAMPS 1
#if NA9_FEED_TIMESTAMPS
static BOOL na9_yes(id self, SEL _cmd) { return YES; }

// Hanya class di executable utama yang namanya berkaitan dengan tampilan feed/penulis/waktu yang diperiksa.
// (Memindai SEMUA class memaksa runtime merealisasi puluhan ribu class: lambat dan boros memori.)
static BOOL NA9NameLooksRelevant(const char *nm) {
    static const char *keys[] = { "TimeStamp", "Timestamp", "Author", "UserName", "Nickname",
                                  "Interaction", "Description", "FeedCell", "PostTime", "CreateTime" };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++)
        if (strcasestr(nm, keys[i])) return YES;
    return NO;
}

static void NA9PatchTimestampFlag(void) {
    SEL sel = NSSelectorFromString(@"shouldShowTimeStampLabel");
    const char *exe = [[NSBundle mainBundle] executablePath].fileSystemRepresentation;
    if (!exe) return;
    unsigned int n = 0;
    const char **names = objc_copyClassNamesForImage(exe, &n);       // hanya nama, tanpa merealisasi class
    if (!names) return;
    for (unsigned int i = 0; i < n; i++) {
        if (!NA9NameLooksRelevant(names[i])) continue;
        Class c = objc_getClass(names[i]);
        if (!c) continue;
        for (int pass = 0; pass < 2; pass++) {
            Class k = pass ? object_getClass(c) : c;                  // pass 1 = class method
            Method m = class_getInstanceMethod(k, sel);
            if (!m) continue;
            Class sup = class_getSuperclass(k);
            if (sup && class_getInstanceMethod(sup, sel) == m) continue;   // warisan, bukan milik k
            if (method_getNumberOfArguments(m) != 2) continue;
            char *rt = method_copyReturnType(m);
            BOOL boolish = rt && (rt[0] == 'B' || rt[0] == 'c');
            free(rt);
            if (!boolish || method_getImplementation(m) == (IMP)na9_yes) continue;
            method_setImplementation(m, (IMP)na9_yes);
            NSLog(@"[NA9AgeSuffix] timestamp flag: %s%s", pass ? "+" : "-", names[i]);
        }
    }
    free(names);
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
    }
}
