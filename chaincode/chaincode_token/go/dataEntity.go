package main

import (
	"encoding/json"
	"strconv"
)

/*
 * 前后台交互数据结构定义
 * 1. 接口请求结构以Request结尾，返回结构以Response结尾
 * 2. 多模块公用的请求或返回结构定义放在该文件中，模块独立使用的定义在模块文件内部
 */

type AccountTokenResponse struct {
	Name  string `json:"name"`
	Token int64  `json:"token"`
}

func (a *AccountTokenResponse) toBytes() []byte {
	dataAsBytes, _ := json.Marshal(a)
	return dataAsBytes
}

type DataEvidenceRequest struct {
	Type  int    `json:"type"`  /*数据类型*/
	Owner string `json:"owner"` /*数据归属方*/
	Title string `json:"title"` /*数据标签名称*/
	Hash  string `json:"hash"`  /*数据Hash*/
}

func (d *DataEvidenceRequest) getDataCompositeKeyAttributes() []string {
	attributes := []string{strconv.Itoa(d.Type), d.Owner, d.Title, d.Hash}
	return attributes
}

func (d *DataEvidenceRequest) getDataTitleCompositeKeyAttributes() []string {
	attributes := []string{strconv.Itoa(d.Type), d.Owner, d.Title}
	return attributes
}

func (d *DataEvidenceRequest) getDataTransferCompositeKeyAttributes(buyer string) []string {
	attributes := []string{buyer, strconv.Itoa(d.Type), d.Owner, d.Title}
	return attributes
}