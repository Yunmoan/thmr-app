package cn.yunmoan.thmr.thmr_app;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import java.io.File;
import java.util.Arrays;

/** Opens Android's installer only for a newer APK signed by our current signer. */
final class UpdateInstaller {
    private static Signature[] signers(PackageInfo info) {
        if (Build.VERSION.SDK_INT >= 28 && info.signingInfo != null) {
            return info.signingInfo.hasMultipleSigners()
                ? info.signingInfo.getApkContentsSigners()
                : info.signingInfo.getSigningCertificateHistory();
        }
        return info.signatures;
    }

    static String install(Activity activity, String rawPath, String version, long buildNumber) throws Exception {
        File file = new File(rawPath).getCanonicalFile();
        File allowed = new File(activity.getCacheDir(), "thmr-updates").getCanonicalFile();
        if (!file.getPath().startsWith(allowed.getPath() + File.separator) ||
                !file.isFile() || !file.getName().endsWith(".apk")) {
            throw new SecurityException("Invalid update file location");
        }
        PackageManager pm = activity.getPackageManager();
        int flags = Build.VERSION.SDK_INT >= 28
            ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
        PackageInfo next = pm.getPackageArchiveInfo(file.getPath(), flags);
        PackageInfo current = pm.getPackageInfo(activity.getPackageName(), flags);
        long nextCode = next == null ? -1 : Build.VERSION.SDK_INT >= 28 ? next.getLongVersionCode() : next.versionCode;
        long currentCode = Build.VERSION.SDK_INT >= 28 ? current.getLongVersionCode() : current.versionCode;
        if (next == null || !activity.getPackageName().equals(next.packageName) ||
                !version.equals(next.versionName) || nextCode != buildNumber || nextCode <= currentCode) {
            throw new SecurityException("APK package or version does not match the update");
        }
        Signature[] before = signers(current);
        Signature[] after = signers(next);
        boolean matching = false;
        if (before != null && after != null) {
            // Android validates the complete signer/rotation policy again during installation.
            if (Build.VERSION.SDK_INT >= 28 && current.signingInfo != null &&
                    current.signingInfo.hasMultipleSigners()) {
                matching = Arrays.equals(before, after);
            } else {
                for (Signature a : before) for (Signature b : after) {
                    if (a.equals(b)) matching = true;
                }
            }
        }
        if (!matching) throw new SecurityException("APK signing certificate differs from the installed application");
        if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
            activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + activity.getPackageName())));
            return "permission_required";
        }
        Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".updater", file);
        Intent intent = new Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.startActivity(intent);
        return "installer_started";
    }
}
