package main

import (
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
	"strconv"
	"time"
)

/*
 * 数据交易合约实现：
 * 1. 数据交易记录管理
 * 2. 数据交易记录索引管理
 */

type DataTransferRecord struct {
	Hash  string `json:"hash"`  /*数据Hash*/
	Price int    `json:"price"` /*实际交易价格*/
	Time  int64  `json:"time"`  /*交易时间*/
	Size  int    `json:"size"`  /*交易数据记录数*/
}

func (d *DataTransferRecord) toBytes() []byte {
	dataAsBytes, _ := json.Marshal(d)
	return dataAsBytes
}

func GetTransferRecordCompositeKey(stub shim.ChaincodeStubInterface, attributes []string) (string, string) {
	indexName := "transfer"
	indexKey, err := stub.CreateCompositeKey(indexName, attributes)
	if err != nil {
		fmt.Printf("GetTransferRecordCompositeKey error: %s \n", err.Error())
	}
	return indexKey, indexName
}

func GetTransferRecord(stub shim.ChaincodeStubInterface, key string) (*DataTransferRecord, error) {
	dataAsBytes, _ := stub.GetState(key)
	if dataAsBytes == nil {
		return nil, fmt.Errorf("can't find transfer record by key %s", key)
	}

	var record DataTransferRecord
	err := json.Unmarshal(dataAsBytes, &record)
	if err != nil {
		return nil, err
	}
	return &record, nil
}

type TransferRequest struct {
	Buyer string                `json:"buyer"`
	Data  []DataEvidenceRequest `json:"data"`
}

type TransferRecordResponse struct {
	Buyer  string             `json:"buyer"`
	Type   int                `json:"type"`
	Owner  string             `json:"owner"`
	Title  string             `json:"title"`
	Record DataTransferRecord `json:"record"`
}

type DownloadTitle struct {
	Title  string `json:"title"`
	Hash   string `json:"hash"`
	Extend string `json:"extend,omitempty"` /*数据扩展信息，请求可以不填写*/
}

type TransferCheckRequest struct {
	Buyer string          `json:"buyer"`
	Type  int             `json:"type"`
	Owner string          `json:"owner"`
	Data  []DownloadTitle `json:"data"` /*待校验交易的数据*/
}

func (t *TransferCheckRequest) getTransferRecordCompositeKeyAttributes(title string) []string {
	attributes := []string{t.Buyer, strconv.Itoa(t.Type), t.Owner, title}
	return attributes
}

func (t *TransferCheckRequest) getDataCompositeKeyAttributes(title, hash string) []string {
	attributes := []string{strconv.Itoa(t.Type), t.Owner, title, hash}
	return attributes
}

type TransferCheckResponse struct {
	Type  int             `json:"type"`
	Owner string          `json:"owner"`
	Data  []DownloadTitle `json:"data"` /*已交易的数据*/
}

// 功能实现中间数据结构定义
type DataTransferEntity struct {
	Core        DataEvidenceRequest `json:"core"` /*数据基础信息*/
	Description *DataDescription    `json:"description"`
	Price       int                 `json:"price"` /*实际交易价格*/
}

type TransferContract struct {
}

func (s *TransferContract) transferData(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	if len(args) != 1 {
		return shim.Error("[transferData] Incorrect number of arguments. Expecting 1")
	}

	var request TransferRequest
	if err := json.Unmarshal([]byte(args[0]), &request); err != nil {
		return shim.Error("[transferData] Failed to parse request.")
	}

	fromAccount, err := GetAccount(stub, request.Buyer)
	if err != nil {
		return shim.Error(fmt.Sprintf("transfer from account [%s] is not exist.", request.Buyer))
	}
	fmt.Printf("transferToken fromAccount - begin [%s %d] \n", fromAccount.Name, fromAccount.Token)

	if address := GetCreatorAddress(stub); address != nil {
		/*if fromAccount.Address != string(address) {
			return shim.Error("Incorrect address of from account")
		}*/
	} else {
		fmt.Printf("transfer data creator address is %s \n", string(address))
	}

	// 数据交易费用：标签价格 * 数据条数
	var toAccountData = make(map[string]int64)
	var validData = make(map[string]*DataTransferEntity)
	for _, info := range request.Data {
		dataDetail, err1 := GetDataDescription(stub, info.getDataCompositeKeyAttributes())
		if err1 != nil {
			return shim.Error(err1.Error())
		}

		dataTitleKey, _ := GetDataTitleCompositeKey(stub, info.getDataTitleCompositeKeyAttributes())
		dataTitle, err := GetDataTitle(stub, dataTitleKey)
		if err != nil {
			return shim.Error(err.Error())
		}

		if _, ok := toAccountData[info.Owner]; !ok {
			toAccountData[info.Owner] = 0
		}
		toAccountData[info.Owner] += int64(dataTitle.Price.Value * dataDetail.Size)
		validData[info.Hash] = &DataTransferEntity{
			Core:        info,
			Description: dataDetail,
			Price:       dataTitle.Price.Value,
		}
	}

	if len(toAccountData) == 0 || len(validData) == 0 {
		return shim.Error("Transfer details or accounts are empty.")
	}

	result, err := s.transferToken(stub, fromAccount, toAccountData)
	if err != nil {
		return shim.Error(err.Error())
	} else {
		s.createTransferRecord(stub, fromAccount.Name, validData)
	}

	return shim.Success(result)
}

func (s *TransferContract) transferToken(stub shim.ChaincodeStubInterface, from *Account, toAccounts map[string]int64) ([]byte, error) {

	for _to, amount := range toAccounts {
		toAccount, err := GetAccount(stub, _to)
		if err != nil {
			fmt.Printf("failed to get account %s \n", _to)
			return nil, err
		}
		msg, result := from.transfer(toAccount, amount)
		if !result {
			fmt.Printf("failed to transfer token, message: %s \n", msg)
			return nil, fmt.Errorf("%s", msg)
		}

		toAccountKey, _ := GetAccountCompositeKey(stub, toAccount.Name)
		err = stub.PutState(toAccountKey, toAccount.toBytes())
		if err != nil {
			fmt.Printf("failed to transfer token to %s, message: %s \n", toAccount.Name, err.Error())
			return nil, err
		}
		fmt.Printf("transferData to account [%s %d] \n", toAccount.Name, toAccount.Token)
	}

	fromAccountKey, _ := GetAccountCompositeKey(stub, from.Name)
	err := stub.PutState(fromAccountKey, from.toBytes())
	if err != nil {
		fmt.Printf("failed to put state to account %s \n", from.Name)
		return nil, err
	}
	fmt.Printf("transferToken fromAccount - end [%s, %d] \n", from.Name, from.Token)

	retData := AccountTokenResponse{Name: from.Name, Token: from.Token}
	retDataAsBytes := retData.toBytes()

	return retDataAsBytes, nil
}

func (s *TransferContract) createTransferRecord(stub shim.ChaincodeStubInterface, from string, validData map[string]*DataTransferEntity) {

	timeUnix := time.Now().Unix()
	for hash, data := range validData {
		transferKey, _ := GetTransferRecordCompositeKey(stub, data.Core.getDataTransferCompositeKeyAttributes(from))
		record := DataTransferRecord{
			Hash:  hash,
			Price: data.Price,
			Time:  timeUnix,
			Size:  data.Description.Size,
		}
		if err := stub.PutState(transferKey, record.toBytes()); err != nil {
			fmt.Printf("Failed to save transfer record, key [%s], message [%s] \n", transferKey, err.Error())
		}
	}
}

func (s *TransferContract) showTransferRecord(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	// args: [buyer, type]
	if len(args) != 2 {
		return shim.Error("[showTransferRecord] Incorrect number of arguments. Expecting 2")
	}

	dataType, err := strconv.Atoi(args[1])
	if err != nil {
		return shim.Error(fmt.Sprintf("[showTitles] Failed to parse data type %s", args[1]))
	}

	var retDataList []TransferRecordResponse
	_, indexName := GetTransferRecordCompositeKey(stub, args)
	resultIterator, _ := stub.GetStateByPartialCompositeKey(indexName, args)
	defer resultIterator.Close()
	for resultIterator.HasNext() {
		item, _ := resultIterator.Next()
		_, attributes, _ := stub.SplitCompositeKey(item.Key)

		var record DataTransferRecord
		_ = json.Unmarshal(item.Value, &record)

		retDataList = append(retDataList, TransferRecordResponse{
			Buyer:  attributes[0],
			Type:   dataType,
			Owner:  attributes[2],
			Title:  attributes[3],
			Record: record,
		})
	}
	retDataListAsBytes, _ := json.Marshal(retDataList)

	return shim.Success(retDataListAsBytes)
}

func (s *TransferContract) checkTransferred(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	if len(args) != 1 {
		return shim.Error("[checkTransferred] Incorrect number of arguments. Expecting 1")
	}

	var request TransferCheckRequest
	if err := json.Unmarshal([]byte(args[0]), &request); err != nil {
		return shim.Error("[checkTransferred] Failed to parse request.")
	}

	retData := TransferCheckResponse{Type: request.Type, Owner: request.Owner}
	for _, data := range request.Data {
		dataAttributes := request.getDataCompositeKeyAttributes(data.Title, data.Hash)
		dataDetail, err := GetDataDescription(stub, dataAttributes)
		if err != nil {
			fmt.Printf("The data isn't exist. message: %s", err.Error())
			return shim.Error(err.Error())
		}

		transferAttributes := request.getTransferRecordCompositeKeyAttributes(data.Title)
		transferRecordKey, _ := GetTransferRecordCompositeKey(stub, transferAttributes)
		if record, err := GetTransferRecord(stub, transferRecordKey); err == nil {
			if record.Hash != data.Hash {
				return shim.Error(fmt.Sprintf("Invalid hash [%s] of transfer record.", record.Hash))
			}
			retData.Data = append(retData.Data, DownloadTitle{
				Title:  data.Title,
				Hash:   data.Title,
				Extend: dataDetail.Extend,
			})
		} else {
			return shim.Error(err.Error())
		}
	}
	retDataAsBytes, _ := json.Marshal(retData)

	return shim.Success(retDataAsBytes)
}
