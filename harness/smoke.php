<?php
/**
 * OPA COMPREHENSIVE smoke-test harness (CLI).
 *
 * Exercises every instrumented surface so the extension produces a rich trace:
 *   - PDO/MySQL queries (incl. a slow SLEEP query, prepared statements)
 *   - mysqli queries
 *   - Redis (phpredis) operations
 *   - APCu cache operations
 *   - outgoing cURL/HTTP requests (200 + 404 to exercise status handling)
 *   - PHP warnings, a caught exception, and error_log() at several levels
 *   - var_dump capture ("dumps")
 *   - nested userland calls (CPU/timing)
 *
 * Each section is guarded so the script always reaches SMOKE_DONE. Section
 * results are printed to stderr with an [ok]/[skip]/[err] marker.
 */

error_reporting(E_ALL);
ini_set('display_errors', 'stderr');

function say($tag, $msg) { fwrite(STDERR, "[$tag] $msg\n"); }
function section($name, callable $fn) {
    try { $fn(); say('ok', $name); }
    catch (\Throwable $e) { say('err', "$name: " . $e->getMessage()); }
}

function fib(int $n): int { return $n < 2 ? $n : fib($n - 1) + fib($n - 2); }

$mysqlHost = getenv('MYSQL_HOST') ?: 'mysql';
$db        = getenv('MYSQL_DATABASE') ?: 'app';
$user      = getenv('MYSQL_USER') ?: 'app';
$pass      = getenv('MYSQL_PASSWORD') ?: 'app';
$redisHost = getenv('REDIS_HOST') ?: 'redis';
$redisPort = (int)(getenv('REDIS_PORT') ?: 6379);
$agent     = 'http://agent:8080';

say('smoke', 'opa.enabled=' . ini_get('opa.enabled')
    . ' service=' . ini_get('opa.service')
    . ' redis=' . $redisHost . ':' . $redisPort);

/* ---------- PDO / MySQL (retry until reachable) ---------- */
$pdo = null;
for ($i = 0; $i < 40; $i++) {
    try {
        $pdo = new PDO("mysql:host=$mysqlHost;port=3306;dbname=$db", $user, $pass,
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        break;
    } catch (Throwable $e) { say('smoke', "waiting for mysql ($i)"); sleep(1); }
}
section('pdo', function () use ($pdo) {
    if (!$pdo) throw new RuntimeException('no MySQL connection');
    $pdo->exec("CREATE TABLE IF NOT EXISTS items (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(64))");
    $pdo->exec("INSERT INTO items (name) VALUES ('alpha'),('beta'),('gamma')");
    $row = $pdo->query("SELECT SLEEP(0.05) AS s, COUNT(*) AS c FROM items")->fetch(PDO::FETCH_ASSOC);
    $q = $pdo->prepare("SELECT * FROM items WHERE name = ?");
    $q->execute(['beta']);
    say('smoke', "pdo rows=" . count($q->fetchAll()) . " count=" . ($row['c'] ?? '?'));
});

/* ---------- mysqli ---------- */
section('mysqli', function () use ($mysqlHost, $db, $user, $pass) {
    $m = @mysqli_connect($mysqlHost, $user, $pass, $db, 3306);
    if (!$m) throw new RuntimeException('mysqli_connect failed: ' . mysqli_connect_error());
    $res = mysqli_query($m, "SELECT COUNT(*) AS c FROM items");
    $r = mysqli_fetch_assoc($res);
    mysqli_query($m, "SELECT SLEEP(0.02)");
    mysqli_close($m);
    say('smoke', "mysqli count=" . ($r['c'] ?? '?'));
});

/* ---------- Redis (phpredis) ---------- */
section('redis', function () use ($redisHost, $redisPort) {
    if (!class_exists('Redis')) throw new RuntimeException('phpredis not installed');
    $r = new Redis();
    if (!$r->connect($redisHost, $redisPort, 2.0)) throw new RuntimeException('redis connect failed');
    $r->set('opa:smoke:key', 'value1');
    $r->get('opa:smoke:key');
    $r->incr('opa:smoke:counter');
    $r->exists('opa:smoke:key');
    $r->hSet('opa:smoke:hash', 'f1', 'v1');
    $r->hGet('opa:smoke:hash', 'f1');
    $r->expire('opa:smoke:key', 60);
    $r->del('opa:smoke:key');
    $r->close();
    say('smoke', 'redis ops done');
});

/* ---------- APCu cache ---------- */
section('apcu', function () {
    if (!function_exists('apcu_store')) throw new RuntimeException('apcu not installed');
    if (!apcu_enabled()) throw new RuntimeException('apcu not enabled (need apc.enable_cli=1)');
    apcu_store('opa:apcu:k', ['a' => 1, 'b' => 2], 60);
    $hit = apcu_fetch('opa:apcu:k', $ok);
    apcu_exists('opa:apcu:k');
    apcu_fetch('opa:apcu:missing', $miss);   // miss
    apcu_delete('opa:apcu:k');
    say('smoke', 'apcu hit=' . ($ok ? 'yes' : 'no'));
});

/* ---------- outgoing HTTP via cURL (200 + 404) ---------- */
section('curl', function () use ($agent) {
    foreach ([['/api/health', 200], ['/api/does-not-exist', 404]] as [$path, $want]) {
        $ch = curl_init($agent . $path);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 5);
        $resp = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        say('smoke', "curl $path -> HTTP $code (want $want)");
    }
    // Request carrying secrets in a header and query string (to verify redaction).
    $ch = curl_init($agent . '/api/health?token=supersecret123&user=bob');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Authorization: Bearer supersecret123', 'X-Api-Key: abc123']);
    curl_exec($ch);
    curl_close($ch);
    say('smoke', 'curl with secret header+query sent');
});

/* ---------- errors, exceptions, logs ---------- */
section('errors_logs', function () {
    error_log('[smoke] info-level log line');
    error_log('[smoke] another log line for correlation');
    // A PHP warning (non-fatal)
    @file_get_contents('/nonexistent/path/for/warning');
    // A caught exception
    try { throw new RuntimeException('smoke: intentional caught exception'); }
    catch (\Throwable $e) { error_log('[smoke] caught: ' . $e->getMessage()); }
    // An UNCAUGHT (non-fatal) warning to exercise error capture (error_instances).
    $arr = [];
    $ignored = @$arr['definitely_missing'];       // undefined-key (kept quiet)
    trigger_error('smoke: uncaught user warning', E_USER_WARNING); // NOT suppressed
    $n = null;
    $len = @strlen((string)$n);                    // benign, keeps going
    say('smoke', 'errors/logs emitted (incl. 1 uncaught warning)');
});

/* ---------- var dumps ---------- */
section('dumps', function () {
    $data = ['user' => 'alice', 'roles' => ['admin', 'viewer'], 'n' => 42];
    ob_start(); var_dump($data); ob_end_clean();   // extension may capture var_dump
    if (function_exists('opa_dump')) { opa_dump($data, 'smoke-dump'); }
    say('smoke', 'dumps emitted');
});

/* ---------- CPU / nested calls ---------- */
section('cpu', function () {
    $t0 = microtime(true);
    $f  = fib(24);
    say('smoke', "fib(24)=$f in " . round((microtime(true) - $t0) * 1000, 2) . "ms");
});

echo "SMOKE_DONE\n";
