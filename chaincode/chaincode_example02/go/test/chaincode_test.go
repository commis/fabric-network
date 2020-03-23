package test

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"
)

type Account struct {
	Name      string `json:"name"`      /*账户名称*/
	Password  string `json:"password"`  /*账户基本信息*/
	Type      int    `json:"type"`      /*账户类别：企业、政府*/
	OrgName   string `json:"orgName"`   /*企业或组织名称*/
	PublicKey string `json:"publicKey"` /*账户公钥信息*/
	Frozen    bool   `json:"-"`         /*账户停用标记*/
	Token     int64  `json:"token"`     /*账户积分*/
}

const creatorCertPem = `
Org2MSP�-----BEGIN CERTIFICATE-----
MIICKjCCAdCgAwIBAgIRAPfJd2ZeGxNXy2gvbwW+yk8wCgYIKoZIzj0EAwIwczEL
MAkGA1UEBhMCVVMxEzARBgNVBAgTCkNhbGlmb3JuaWExFjAUBgNVBAcTDVNhbiBG
cmFuY2lzY28xGTAXBgNVBAoTEG9yZzIuZXhhbXBsZS5jb20xHDAaBgNVBAMTE2Nh
Lm9yZzIuZXhhbXBsZS5jb20wHhcNMjAwMzA1MDMzODAwWhcNMzAwMzAzMDMzODAw
WjBrMQswCQYDVQQGEwJVUzETMBEGA1UECBMKQ2FsaWZvcm5pYTEWMBQGA1UEBxMN
U2FuIEZyYW5jaXNjbzEOMAwGA1UECxMFYWRtaW4xHzAdBgNVBAMMFkFkbWluQG9y
ZzIuZXhhbXBsZS5jb20wWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARHrML1Rm2V
LiARZzEmVoBvqLXZwr0ulCJ4PhEx1XkvWxSO4n5pHUgG8yKCux7nQFqRgwgYJK2F
HYeRc4aDbR2qo00wSzAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADArBgNV
HSMEJDAigCC9lrKwUnOtmNKxDA38zwocQ5PTxLzWg1RK78ARNm78CjAKBggqhkjO
PQQDAgNIADBFAiEA9UA4MHbMNpqQEchlTzlGRLZmy7h5TN8lKjpebB79K24CIBI3
ODWxjfNx1nYqQMFrZkIxi29uH5+1v3ICB2zfNDCb
-----END CERTIFICATE-----
`
const BeginCert = "-----BEGIN CERTIFICATE-----"
const EndCert = "-----END CERTIFICATE-----"

func TestParseCert(t *testing.T) {
	/*begin := strings.Index(creatorCertPem, BeginCert)
	end := strings.Index(creatorCertPem, EndCert) + len(EndCert)
	certPem := creatorCertPem[begin:end]

	pemBlock, _ := pem.Decode([]byte(certPem))
	if pemBlock == nil {
		fmt.Printf("error\n")
		return
	}
	x509Cert, err := x509.ParseCertificate(pemBlock.Bytes)
	if err != nil {
		fmt.Printf("parse certificate error.\n")
		return
	}
	publicKeyDer, _ := x509.MarshalPKIXPublicKey(x509Cert.PublicKey)
	fmt.Printf("%s\n", x509Cert.PublicKeyAlgorithm)
	fmt.Printf("%s\n", hex.EncodeToString(publicKeyDer))*/

	timeUnix := time.Now().Unix()
	formatTimeStr := time.Unix(timeUnix, 0).Format("2006-01-02 15:04:05")
	fmt.Println(formatTimeStr)
}

type DownloadTitle struct {
	Title  string `json:"title"`
	Hash   string `json:"hash"`
	Extend string `json:"extend,omitempty"`
}

func TestAccount(t *testing.T) {
	title := DownloadTitle{
		Title:  "haha",
		Hash:   "adfadfasdfasdfasdfasdfa",
		Extend: "asdfasdf",
	}
	titleAsBytes, _ := json.Marshal(title)
	fmt.Printf("searchTitles m %v \n", string(titleAsBytes))
}
