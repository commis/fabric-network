package main

import (
	"encoding/json"
	"fmt"
	"github.com/hyperledger/fabric-chaincode-go/shim"
	pb "github.com/hyperledger/fabric-protos-go/peer"
	"strconv"
)

/*
 * 数据合约实现：
 * 1. 数据标签基本信息存证
 * 2. 数据标签信息管理(价格、上下架)
 * 3. 数据标签归属索引管理
 */

type DataRequest struct {
	Core        DataEvidenceRequest `json:"core"`        /*数据核心信息*/
	Description DataDescription     `json:"description"` /*数据扩展描述信息*/
}

func (d *DataRequest) toString() string {
	dataAsBytes, _ := json.Marshal(d)
	return string(dataAsBytes)
}

type DataDescription struct {
	Size   int    `json:"size"`             /*文件记录条数*/
	Extend string `json:"extend,omitempty"` /*数据其他扩展信息，JSON格式数据，供数据方使用*/
}

func (d *DataDescription) toBytes() []byte {
	dataAsBytes, _ := json.Marshal(d)
	return dataAsBytes
}

func GetDataCompositeKey(stub shim.ChaincodeStubInterface, attributes []string) (string, string) {
	indexName := "data"
	indexKey, err := stub.CreateCompositeKey(indexName, attributes)
	if err != nil {
		fmt.Printf("GetDataCompositeKey error: %s \n", err.Error())
	}
	return indexKey, indexName
}

func GetDataDescription(stub shim.ChaincodeStubInterface, attributes []string) (*DataDescription, error) {
	dataKey, _ := GetDataCompositeKey(stub, attributes)
	dataAsBytes, _ := stub.GetState(dataKey)
	if dataAsBytes == nil {
		return nil, fmt.Errorf("can't find data detail by key %s", dataKey)
	}

	description := DataDescription{}
	err := json.Unmarshal(dataAsBytes, &description)
	if err != nil {
		return nil, err
	}
	return &description, nil
}

type DataTitlePrice struct {
	Min   int `json:"min,omitempty"` /*价格区间最小值*/
	Max   int `json:"max,omitempty"` /*价格区间最大值*/
	Value int `json:"value"`         /*当前使用价格值*/
}

func (p *DataTitlePrice) valid() error {
	err := p.validRange()
	if err == nil {
		return p.validValue(p.Value)
	} else {
		return err
	}
}

func (p *DataTitlePrice) validValue(value int) error {
	if value >= p.Min && value <= p.Max {
		return nil
	}
	return fmt.Errorf("数据值[%d]超出范围[%d ~ %d]", value, p.Min, p.Max)
}

func (p *DataTitlePrice) validRange() error {
	if p.Min >= 1 && p.Max >= 1 && p.Min < p.Max {
		return nil
	}
	return fmt.Errorf("数据价格范围[%d ~ %d]无效", p.Min, p.Max)
}

func (p *DataTitlePrice) setRange(min int, max int) {
	p.Min = min
	p.Max = max
}

func (p *DataTitlePrice) toString() string {
	priceAsBytes, _ := json.Marshal(p)
	return string(priceAsBytes)
}

type DataTitleRequest struct {
	Type   int            `json:"type"`   /*数据类型*/
	Owner  string         `json:"owner"`  /*数据归属方*/
	Title  string         `json:"title"`  /*数据标签名称*/
	Shelve bool           `json:"shelve"` /*标签是否上架*/
	Price  DataTitlePrice `json:"price"`  /*数据标签价格*/
}

type DataTitleDescription struct {
	Shelve bool           `json:"shelve"`
	Price  DataTitlePrice `json:"price"`
}

func (d *DataTitleDescription) toBytes() []byte {
	dataAsBytes, err := json.Marshal(d)
	if err != nil {
		fmt.Printf("[DataTitleDescription] marshall failed.\n")
		return []byte{}
	}
	return dataAsBytes
}

func (d *DataTitleDescription) toString() string {
	dataAsBytes, _ := json.Marshal(d)
	return string(dataAsBytes)
}

func GetDataTitleCompositeKey(stub shim.ChaincodeStubInterface, attributes []string) (string, string) {
	indexName := "title"
	indexKey, err := stub.CreateCompositeKey(indexName, attributes)
	if err != nil {
		fmt.Printf("GetDataTitleCompositeKey error: %s \n", err.Error())
	}
	return indexKey, indexName
}

func GetDataTitle(stub shim.ChaincodeStubInterface, key string) (*DataTitleDescription, error) {
	dataAsBytes, _ := stub.GetState(key)
	if dataAsBytes != nil {
		titleDescription := DataTitleDescription{}
		if err := json.Unmarshal(dataAsBytes, &titleDescription); err != nil {
			return nil, fmt.Errorf("[GetDataTitle] Failed to Unmarshal json %s \n", string(dataAsBytes))
		}
		return &titleDescription, nil
	}
	return nil, fmt.Errorf("can't find title detail by key %s", key)
}

type SearchTitleRequest struct {
	Type   int      `json:"type"`   /*数据类型*/
	Owner  string   `json:"owner"`  /*数据归属方*/
	Titles []string `json:"titles"` /*搜索标签名列表*/
}

func (s *SearchTitleRequest) getDataTitleCompositeKeyAttributes(title string) []string {
	attributes := []string{strconv.Itoa(s.Type), s.Owner, title}
	return attributes
}

func (s *SearchTitleRequest) getDataTitlePartialCompositeKeyAttributes() []string {
	attributes := []string{strconv.Itoa(s.Type), s.Owner}
	return attributes
}

type SearchTitleResponse struct {
	Base   DataTitleRequest `json:"base"`   /*数据标签基本信息*/
	Hash   string           `json:"hash"`   /*数据Hash*/
	Extend string           `json:"extend"` /*数据扩展描述信息*/
}

type OwnerTitleResponse struct {
	Type  int                 `json:"type"`
	Title map[string][]string `json:"titles"`
}

func (o *OwnerTitleResponse) toBytes() []byte {
	dataAsBytes, _ := json.Marshal(o)
	return dataAsBytes
}

type DataContract struct {
}

func (s *DataContract) setDataEvidence(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	if len(args) != 1 {
		return shim.Error("[setDataEvidence] Incorrect number of arguments. Expecting 1")
	}

	_param := args[0]

	var request DataRequest
	if err := json.Unmarshal([]byte(_param), &request); err != nil {
		fmt.Println("Failed to parse data entity.")
		return shim.Error("Failed to parse data entity.")
	}

	dataKey, _ := GetDataCompositeKey(stub, request.Core.getDataCompositeKeyAttributes())
	dataDetailAsBytes := request.Description.toBytes()

	if err := stub.PutState(dataKey, dataDetailAsBytes); err != nil {
		return shim.Error(err.Error())
	} else {
		fmt.Printf("setDataEvidence - end %s = %s \n", dataKey, string(dataDetailAsBytes))
	}

	return shim.Success(nil)
}

func (s *DataContract) showDataEvidence(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	if len(args) != 1 {
		return shim.Error("[showDataEvidence] Incorrect number of arguments. Expecting 1")
	}

	var requestList []DataEvidenceRequest
	if err := json.Unmarshal([]byte(args[0]), &requestList); err != nil {
		return shim.Error("[showDataEvidence] Failed to parse request.")
	}

	var retDataList []DataRequest
	for _, info := range requestList {
		attributes := info.getDataCompositeKeyAttributes()
		if dataDetail, err := GetDataDescription(stub, attributes); err == nil {
			retDataList = append(retDataList, DataRequest{
				Core:        info,
				Description: *dataDetail,
			})
		} else {
			fmt.Printf("Invalid key of data detail. [%v] \n", attributes)
			return shim.Error(err.Error())
		}
	}
	retDataListAsBytes, _ := json.Marshal(retDataList)

	return shim.Success(retDataListAsBytes)
}

func (s *DataContract) setTitle(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	if len(args) != 1 {
		return shim.Error("[setTitle] Incorrect number of arguments. Expecting 1")
	}

	var dataTitle DataTitleRequest
	if err := json.Unmarshal([]byte(args[0]), &dataTitle); err != nil {
		return shim.Error("[setTitle] Incorrect argument. Expecting a json string of data title.")
	}

	dataTitleKey, _ := GetDataTitleCompositeKey(stub, []string{strconv.Itoa(dataTitle.Type), dataTitle.Owner, dataTitle.Title})
	_existDataTitle, err := GetDataTitle(stub, dataTitleKey)
	if err != nil {
		// 数据不存在，新增加数据
		if err := dataTitle.Price.valid(); err != nil {
			return shim.Error(err.Error())
		}
		_existDataTitle = &DataTitleDescription{
			Shelve: dataTitle.Shelve,
			Price:  dataTitle.Price,
		}
	} else {
		_existDataTitle.Shelve = dataTitle.Shelve
		// 调整数据价格区间
		if err := dataTitle.Price.validRange(); err != nil {
			return shim.Error(err.Error())
		}
		_existDataTitle.Price.setRange(dataTitle.Price.Min, dataTitle.Price.Max)
		// 调整数据价格值
		if dataTitle.Price.Value > 0 {
			if err := _existDataTitle.Price.validValue(dataTitle.Price.Value); err != nil {
				return shim.Error(err.Error())
			}
			_existDataTitle.Price.Value = dataTitle.Price.Value
		}
		if err := _existDataTitle.Price.valid(); err != nil {
			return shim.Error(err.Error())
		}
	}

	// 更新标签数据状态
	if err = stub.PutState(dataTitleKey, _existDataTitle.toBytes()); err != nil {
		return shim.Error(err.Error())
	} else {
		fmt.Printf("setTitle - end %s = %s \n", dataTitleKey, _existDataTitle.toString())
	}

	return shim.Success(nil)
}

func (s *DataContract) showTitles(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	// args: [type, owner]
	if len(args) != 2 {
		return shim.Error("[showTitles] Incorrect number of arguments. Expecting 2")
	}

	dataType, err := strconv.Atoi(args[0])
	if err != nil {
		return shim.Error(fmt.Sprintf("[showTitles] Failed to parse data type %s", args[0]))
	}

	var retDataList []DataTitleRequest
	_, indexName := GetDataTitleCompositeKey(stub, args)
	resultIterator, _ := stub.GetStateByPartialCompositeKey(indexName, args)
	defer resultIterator.Close()
	for resultIterator.HasNext() {
		item, _ := resultIterator.Next()
		_, attributes, _ := stub.SplitCompositeKey(item.Key)

		titleDetail := DataTitleDescription{}
		_ = json.Unmarshal(item.Value, &titleDetail)
		// fmt.Printf("showTitles info: %s = %s \n", item.Key, titleDetail.toString())
		retDataList = append(retDataList, DataTitleRequest{
			Type:   dataType,
			Owner:  attributes[1],
			Title:  attributes[2],
			Shelve: titleDetail.Shelve,
			Price:  titleDetail.Price,
		})
	}
	retDataListAsBytes, _ := json.Marshal(retDataList)

	return shim.Success(retDataListAsBytes)
}

func (s *DataContract) showNameOfTitles(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	// args: [type]
	if len(args) != 1 {
		return shim.Error("[showNameOfTitles] Incorrect number of arguments. Expecting 1")
	}

	dataType, err := strconv.Atoi(args[0])
	if err != nil {
		return shim.Error(fmt.Sprintf("[showNameOfTitles] Incorrect format of argument. Expecting number."))
	}

	var retData = OwnerTitleResponse{Type: dataType}
	_, indexName := GetDataTitleCompositeKey(stub, args)
	resultIterator, _ := stub.GetStateByPartialCompositeKey(indexName, args)
	defer resultIterator.Close()

	retData.Title = make(map[string][]string)
	for resultIterator.HasNext() {
		item, _ := resultIterator.Next()
		_, attributes, _ := stub.SplitCompositeKey(item.Key)

		if titleDetail, err := GetDataTitle(stub, item.Key); err == nil {
			if !titleDetail.Shelve {
				continue
			}
		} else {
			return shim.Error(err.Error())
		}

		owner := attributes[1]
		title := attributes[2]
		if _, ok := retData.Title[owner]; ok {
			retData.Title[owner] = append(retData.Title[owner], title)
		} else {
			retData.Title[owner] = []string{title}
		}
	}
	retDataListAsBytes := retData.toBytes()

	return shim.Success(retDataListAsBytes)
}

func (s *DataContract) searchTitles(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	if len(args) != 1 {
		return shim.Error("[searchTitles] Incorrect number of arguments. Expecting 1")
	}

	searchRequest := SearchTitleRequest{}
	if err := json.Unmarshal([]byte(args[0]), &searchRequest); err != nil {
		return shim.Error("[searchTitles] Incorrect argument. Expecting a json string.")
	}

	var retDataList []SearchTitleResponse
	for _, title := range searchRequest.Titles {
		titleReqArgs := searchRequest.getDataTitleCompositeKeyAttributes(title)
		titleKey, _ := GetDataTitleCompositeKey(stub, titleReqArgs)
		if titleDetail, err := GetDataTitle(stub, titleKey); err == nil {
			if !titleDetail.Shelve {
				continue
			}

			_, dataIndexName := GetDataCompositeKey(stub, titleReqArgs)
			dataIterator, _ := stub.GetStateByPartialCompositeKey(dataIndexName, titleReqArgs)
			defer dataIterator.Close()
			for dataIterator.HasNext() {
				item, _ := dataIterator.Next()

				var dataDetail DataDescription
				_ = json.Unmarshal(item.Value, &dataDetail)

				_, dataAttributes, _ := stub.SplitCompositeKey(item.Key)
				retDataList = append(retDataList, SearchTitleResponse{
					Base: DataTitleRequest{
						Type:   searchRequest.Type,
						Owner:  searchRequest.Owner,
						Title:  title,
						Shelve: titleDetail.Shelve,
						Price:  titleDetail.Price,
					},
					Hash:   dataAttributes[3],
					Extend: dataDetail.Extend,
				})
			}
		} else {
			fmt.Println(err.Error())
		}
	}
	retDataListAsBytes, _ := json.Marshal(retDataList)

	return shim.Success(retDataListAsBytes)
}
