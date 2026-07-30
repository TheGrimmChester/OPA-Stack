<?php
/**
 * Wave 30 IAST detect + optional block smoke for opa-php:smoke.
 *
 * Runs inside php-cli with:
 *   OPA_IAST=1 OPA_IAST_BLOCK=1 (or -d opa.iast=1 -d opa.iast_block=1)
 *
 * Expects: dangerous SQL is blocked (mysqli_query returns false) when block is on.
 */
error_reporting(E_ALL);
ini_set('display_errors', '1');

$block = (bool) (ini_get('opa.iast_block') ?: getenv('OPA_IAST_BLOCK'));
$iast = (bool) (ini_get('opa.iast') ?: getenv('OPA_IAST'));
fwrite(STDOUT, "iast=" . ($iast ? '1' : '0') . " block=" . ($block ? '1' : '0') . "\n");
fwrite(STDOUT, "extension_loaded(opa)=" . (extension_loaded('opa') ? '1' : '0') . "\n");

$host = getenv('MYSQL_HOST') ?: 'mysql';
$db = getenv('MYSQL_DATABASE') ?: 'app';
$user = getenv('MYSQL_USER') ?: 'app';
$pass = getenv('MYSQL_PASSWORD') ?: 'app';

$m = @mysqli_connect($host, $user, $pass, $db, 3306);
if (!$m) {
    fwrite(STDERR, "mysqli_connect failed: " . mysqli_connect_error() . "\n");
    exit(2);
}

$safe = mysqli_query($m, "SELECT 1 AS ok");
if (!$safe) {
    fwrite(STDERR, "safe query unexpectedly failed\n");
    exit(3);
}
fwrite(STDOUT, "safe_query=ok\n");

$danger = "SELECT * FROM items WHERE id = '" . ($_GET['id'] ?? "1' OR '1'='1") . "'";
$res = @mysqli_query($m, $danger);
$blocked = ($res === false);

if ($block) {
    if (!$blocked) {
        fwrite(STDERR, "FAIL: expected IAST block to reject dangerous SQL\n");
        mysqli_close($m);
        exit(1);
    }
    fwrite(STDOUT, "dangerous_query=blocked (ok)\n");
} else {
    fwrite(STDOUT, "dangerous_query=" . ($blocked ? 'failed' : 'ran') . " (detect-only mode)\n");
}

mysqli_close($m);
fwrite(STDOUT, "iast-block-smoke: OK\n");
exit(0);
