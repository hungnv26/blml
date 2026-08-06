// URL title lookup for link previews.
//
// GET /v0/urlpreview?url=<escaped url>  ->  {"title": "...", "host": "..."}
//
// The server does the fetching so phones never contact third-party sites for
// previews, and so the SSRF policy lives in exactly one place. This is a BLML
// addition, not upstream code.
package main

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"golang.org/x/net/html"
)

const (
	urlPreviewTimeout  = 5 * time.Second
	urlPreviewMaxBytes = 512 * 1024
)

var urlPreviewClient = &http.Client{
	Timeout: urlPreviewTimeout,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 3 {
			return http.ErrUseLastResponse
		}
		// Redirect targets go through the same address policy as the
		// original URL: a public host 302-ing to 169.254.169.254 is the
		// classic SSRF bypass.
		if err := checkURLAllowed(req.URL); err != nil {
			return err
		}
		return nil
	},
}

type ssrfError struct{ msg string }

func (e *ssrfError) Error() string { return e.msg }

// checkURLAllowed rejects anything that could reach private infrastructure.
func checkURLAllowed(u *url.URL) error {
	if u.Scheme != "http" && u.Scheme != "https" {
		return &ssrfError{"scheme not allowed"}
	}
	host := u.Hostname()
	if host == "" {
		return &ssrfError{"no host"}
	}
	ips, err := net.LookupIP(host)
	if err != nil || len(ips) == 0 {
		return &ssrfError{"host does not resolve"}
	}
	for _, ip := range ips {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
			ip.IsLinkLocalMulticast() || ip.IsUnspecified() {
			return &ssrfError{"address not allowed"}
		}
	}
	return nil
}

var titleRe = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)

// extractTitle prefers og:title, falls back to <title>.
func extractTitle(body []byte) string {
	doc, err := html.Parse(strings.NewReader(string(body)))
	if err == nil {
		var ogTitle, docTitle string
		var walk func(*html.Node)
		walk = func(n *html.Node) {
			if n.Type == html.ElementNode {
				if n.Data == "meta" {
					var prop, content string
					for _, a := range n.Attr {
						switch a.Key {
						case "property", "name":
							prop = a.Val
						case "content":
							content = a.Val
						}
					}
					if prop == "og:title" && content != "" {
						ogTitle = content
					}
				}
				if n.Data == "title" && n.FirstChild != nil && docTitle == "" {
					docTitle = n.FirstChild.Data
				}
			}
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				walk(c)
			}
		}
		walk(doc)
		if ogTitle != "" {
			return strings.TrimSpace(ogTitle)
		}
		if docTitle != "" {
			return strings.TrimSpace(docTitle)
		}
	}
	// Regex fallback for pages the parser chokes on.
	if m := titleRe.FindSubmatch(body); m != nil {
		return strings.TrimSpace(html.UnescapeString(string(m[1])))
	}
	return ""
}

func serveURLPreview(wrt http.ResponseWriter, req *http.Request) {
	wrt.Header().Set("Content-Type", "application/json; charset=utf-8")

	// Same API-key check the file endpoints use: this endpoint makes the
	// server issue outbound requests, so it is not left anonymous.
	if isValid, _ := checkAPIKey(getAPIKey(req)); !isValid {
		wrt.WriteHeader(http.StatusForbidden)
		json.NewEncoder(wrt).Encode(map[string]string{"error": "valid API key required"})
		return
	}

	raw := req.FormValue("url")
	target, err := url.Parse(raw)
	if err != nil || raw == "" {
		wrt.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(wrt).Encode(map[string]string{"error": "bad url"})
		return
	}
	if err := checkURLAllowed(target); err != nil {
		wrt.WriteHeader(http.StatusForbidden)
		json.NewEncoder(wrt).Encode(map[string]string{"error": err.Error()})
		return
	}

	greq, _ := http.NewRequest(http.MethodGet, target.String(), nil)
	greq.Header.Set("User-Agent", "BLML-preview/1.0")
	greq.Header.Set("Accept", "text/html")
	resp, err := urlPreviewClient.Do(greq)
	if err != nil {
		wrt.WriteHeader(http.StatusBadGateway)
		json.NewEncoder(wrt).Encode(map[string]string{"error": "fetch failed"})
		return
	}
	defer resp.Body.Close()

	ct := resp.Header.Get("Content-Type")
	if resp.StatusCode != http.StatusOK || (!strings.Contains(ct, "text/html") && !strings.Contains(ct, "application/xhtml")) {
		wrt.WriteHeader(http.StatusUnsupportedMediaType)
		json.NewEncoder(wrt).Encode(map[string]string{"error": "not an html page"})
		return
	}

	body, _ := io.ReadAll(io.LimitReader(resp.Body, urlPreviewMaxBytes))
	title := extractTitle(body)
	if title == "" {
		wrt.WriteHeader(http.StatusNotFound)
		json.NewEncoder(wrt).Encode(map[string]string{"error": "no title"})
		return
	}

	json.NewEncoder(wrt).Encode(map[string]string{
		"title": title,
		"host":  target.Hostname(),
	})
}
