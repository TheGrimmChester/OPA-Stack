// Minimal, dependency-free OIDC IdP stub for verifying OPA's OIDC receiver.
// Serves discovery, JWKS (RS256) and a token endpoint that returns a signed
// id_token. NOT for production — testing only.
package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

var (
	priv   *rsa.PrivateKey
	issuer string
	kid    = "stub-key-1"
)

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func signJWT(claims map[string]interface{}) string {
	header := map[string]interface{}{"alg": "RS256", "typ": "JWT", "kid": kid}
	hb, _ := json.Marshal(header)
	cb, _ := json.Marshal(claims)
	input := b64(hb) + "." + b64(cb)
	h := sha256.Sum256([]byte(input))
	sig, _ := rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, h[:])
	return input + "." + b64(sig)
}

func main() {
	addr := os.Getenv("STUB_ADDR")
	if addr == "" {
		addr = ":9500"
	}
	issuer = os.Getenv("STUB_ISSUER")
	if issuer == "" {
		issuer = "http://oidc-stub:9500"
	}
	var err error
	priv, err = rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/.well-known/openid-configuration", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]interface{}{
			"issuer":                 issuer,
			"authorization_endpoint": issuer + "/authorize",
			"token_endpoint":         issuer + "/token",
			"jwks_uri":               issuer + "/jwks",
		})
	})

	http.HandleFunc("/jwks", func(w http.ResponseWriter, r *http.Request) {
		e := big.NewInt(int64(priv.E)).Bytes()
		json.NewEncoder(w).Encode(map[string]interface{}{
			"keys": []map[string]interface{}{{
				"kty": "RSA", "use": "sig", "alg": "RS256", "kid": kid,
				"n": b64(priv.N.Bytes()), "e": b64(e),
			}},
		})
	})

	// Browser hop: redirect straight back with a fixed code.
	http.HandleFunc("/authorize", func(w http.ResponseWriter, r *http.Request) {
		redirectURI := r.URL.Query().Get("redirect_uri")
		state := r.URL.Query().Get("state")
		u, _ := url.Parse(redirectURI)
		q := u.Query()
		q.Set("code", "stub-code")
		q.Set("state", state)
		u.RawQuery = q.Encode()
		http.Redirect(w, r, u.String(), http.StatusFound)
	})

	http.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		clientID := r.Form.Get("client_id")
		now := time.Now()
		groups := os.Getenv("STUB_GROUPS") // e.g. "opa-admins"
		var groupsClaim interface{} = []string{}
		if groups != "" {
			groupsClaim = strings.Split(groups, ",")
		}
		idToken := signJWT(map[string]interface{}{
			"iss":    issuer,
			"aud":    clientID,
			"sub":    "stub-user-1",
			"email":  "sso.user@example.com",
			"name":   "SSO User",
			"groups": groupsClaim,
			"iat":    now.Unix(),
			"exp":    now.Add(time.Hour).Unix(),
		})
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "stub-access", "token_type": "Bearer",
			"expires_in": 3600, "id_token": idToken,
		})
	})

	fmt.Printf("oidc-stub listening on %s (issuer=%s)\n", addr, issuer)
	log.Fatal(http.ListenAndServe(addr, nil))
}
