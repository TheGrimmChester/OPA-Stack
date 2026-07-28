<?php
// Minimal: no deep recursion, no big stack — just one curl. Tests root-span delivery.
$ch = curl_init('http://agent:8080/api/health');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_exec($ch); curl_close($ch);
echo "TINY_DONE\n";
