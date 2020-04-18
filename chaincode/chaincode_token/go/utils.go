package main

import (
	"crypto/md5"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"github.com/hyperledger/fabric/core/chaincode/shim"
	"reflect"
	"strings"
)

const BeginCert = "-----BEGIN CERTIFICATE-----"
const EndCert = "-----END CERTIFICATE-----"

type AlgorithmType int

const (
	_ AlgorithmType = iota
	MD5
	SHA1
	SHA256
	SHA512
)

type HashUtil struct {
	algor AlgorithmType
}

func (h *HashUtil) checksum(data []byte) string {
	var hashBytes interface{}
	switch h.algor {
	case MD5:
		hashBytes = md5.Sum(data)
	case SHA1:
		hashBytes = sha1.Sum(data)
	case SHA256:
		hashBytes = sha256.Sum256(data)
	case SHA512:
		hashBytes = sha512.Sum512(data)
	default:
		return "UNKNOWN"
	}
	return fmt.Sprintf("%x", hashBytes)
}

func (h *HashUtil) secret(data string) string {
	middle := []byte(data)
	for i := 1; i < 4; i++ {
		sum := sha512.Sum512(middle)
		middle = middle[0:0]
		copy(middle[:], sum[:64])
		sum1 := sha1.Sum(middle)
		middle = middle[0:0]
		copy(middle[:], sum1[:20])
	}
	return fmt.Sprintf("%x", middle)
}

func DefaultHashUtil() HashUtil {
	return HashUtil{algor: SHA1}
}

func Checksum(data []byte) string {
	hashBytes := md5.Sum(data)
	hash := fmt.Sprintf("%x", hashBytes)
	return hash
}

func GetCreatorAddress(stub shim.ChaincodeStubInterface) []byte {
	creator, _ := stub.GetCreator()
	creatorCertPem := string(creator)
	begin := strings.Index(creatorCertPem, BeginCert)
	end := strings.Index(creatorCertPem, EndCert) + len(EndCert)
	certPem := creatorCertPem[begin:end]

	if pemBlock, _ := pem.Decode([]byte(certPem)); pemBlock != nil {
		if x509Cert, err := x509.ParseCertificate(pemBlock.Bytes); err == nil {
			publicKeyBytes, _ := x509.MarshalPKIXPublicKey(x509Cert.PublicKey)
			hashUtil := DefaultHashUtil()
			return []byte(hashUtil.checksum(publicKeyBytes))
		} else {
			fmt.Printf("parse certificate error.\n")
		}
	} else {
		fmt.Printf("decode cert error.\n")
	}
	return nil
}

// 集合去除重复数据
func Duplicate(a interface{}) (ret []interface{}) {
	va := reflect.ValueOf(a)
	for i := 0; i < va.Len(); i++ {
		if i > 0 && reflect.DeepEqual(va.Index(i-1).Interface(), va.Index(i).Interface()) {
			continue
		}
		ret = append(ret, va.Index(i).Interface())
	}
	return ret
}

// 去除首尾空格和换行符
func Trim(data string) string {
	str := data
	newLineFlags := []string{" ", "\n", "\r", "\r\n"}
	for _, flag := range newLineFlags {
		str = strings.Replace(str, flag, "", -1)
	}
	return str
}

// 求并集
func Union(slice1, slice2 []string) []string {
	m := make(map[string]int)
	for _, v := range slice1 {
		m[v]++
	}

	for _, v := range slice2 {
		times, _ := m[v]
		if times == 0 {
			slice1 = append(slice1, v)
		}
	}
	return slice1
}

// 求交集
func Intersect(slice1, slice2 []string) []string {
	m := make(map[string]int)
	nn := make([]string, 0)
	for _, v := range slice1 {
		m[v]++
	}

	for _, v := range slice2 {
		times, _ := m[v]
		if times == 1 {
			nn = append(nn, v)
		}
	}
	return nn
}

// 求差集 slice1-交集
func Difference(slice1, slice2 []string) []string {
	m := make(map[string]int)
	nn := make([]string, 0)
	inter := Intersect(slice1, slice2)
	for _, v := range inter {
		m[v]++
	}

	for _, value := range slice1 {
		times, _ := m[value]
		if times == 0 {
			nn = append(nn, value)
		}
	}
	return nn
}
