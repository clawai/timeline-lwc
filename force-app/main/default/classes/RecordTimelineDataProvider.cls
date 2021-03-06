public with sharing class RecordTimelineDataProvider {
    @AuraEnabled(cacheable=false)
    public static TimelineDataResponse getTimelineItemData(String confIdOrName,String recordId) {
        System.debug('>>>>>>>>>>> confIdOrName='+confIdOrName+', record Id:'+recordId);
        if(recordId !=null && confIdOrName!=null){
            if(areObjectAndFieldsAccessible()){
                Timeline_Configuration__c conf  = [ select Id,timeline__Object__c,
                                                    (SELECT timeline__Date_Field__c,timeline__Fields_to_Display__c,timeline__Icon_Image_Url__c,
                                                            timeline__Icon_Name__c,Id,Name,timeline__Object_Color__c,timeline__Object__c,timeline__Relationship_Name__c,
                                                            timeline__Title_Field__c,timeline__LWC_Ui_Api_Not_Supported__c 
                                                    FROM timeline__Timeline_Child_Objects__r)
                                                    from timeline__Timeline_Configuration__c
                                                    where (Id=:confIdOrName or Name=:confIdOrName)
                                                ];
                String soqlToExec = getSOQLForTimeline(conf, recordId);
                System.debug('>>>>>>>>> '+soqlToExec);
                List<SObject> result = Database.query(soqlToExec);
                SObject theObject = result[0];
                return new TimelineDataResponse(conf,theObject);
            }
            return null;
        }else{
            return null;
        }

    }

    private static Boolean areObjectAndFieldsAccessible(){
        return (Timeline_Configuration__c.sObjectType.getDescribe().isAccessible() &&
                Timeline_Child_Object__c.sObjectType.getDescribe().isAccessible() &&
                Schema.sObjectType.Timeline_Configuration__c.fields.Object__c.isAccessible() && 
                Schema.sObjectType.Timeline_Child_Object__c.fields.Date_Field__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Fields_to_Display__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Icon_Image_Url__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Icon_Name__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Object_Color__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Object__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Relationship_Name__c.isAccessible() &&
                Schema.sObjectType.Timeline_Child_Object__c.fields.Title_Field__c.isAccessible()
        );
    }

    @AuraEnabled(cacheable=true)
    public static EMailMessage getEmailDetails(String taskId) {
        List<EmailMessage> msgs = [ select Id,Subject,FromName,FromAddress,ToAddress,TextBody,
                                          (select RelationId,Relation.Name,RelationObjectType,RelationType
                                          from EmailMessageRelations
                                          where RelationType in('FromAddress','ToAddress')
                                          order by RelationType asc)
                                    from EmailMessage
                                    where ActivityId=:taskId];
        if(!msgs.isEmpty()){
            return msgs[0];
        }
        return null;

    }


    @AuraEnabled(cacheable=true)
    public static TimelineDataResponse getTimelineItemChildData(String objectApiName,String fieldsToExtract,String recordId) {
        //Get all the fields so that we can get labels and type
        List<String> fieldsToQuery = fieldsToExtract.split(',');
        List<ApexDescribeUtils.FieldData> retFieldMetaData = ApexDescribeUtils.getFieldsForObject(objectApiName,fieldsToQuery);
        for(ApexDescribeUtils.FieldData fld:retFieldMetaData){
            System.debug('>>>>>> getTimelineItemChildData: fld '+fld);
            if(fld.isNamePointing){
                System.debug('>>>>>> getTimelineItemChildData: isNamePointing = true');
                fieldsToQuery.add(fld.relationshipName+'.Name');
            }else if(fld.dataType.equalsIgnoreCase('REFERENCE')){
                System.debug('>>>>>> getTimelineItemChildData: REFERENCE field ');
                for(ApexDescribeUtils.FieldData relFldMeta : ApexDescribeUtils.getFieldsForObject(fld.referenceTo)){
                    if(relFldMeta.isNameField){
                        System.debug('>>>>>> getTimelineItemChildData: relFldMeta.apiName ='+relFldMeta.apiName);
                        fld.referenceToApiName=relFldMeta.apiName;
                        fld.fieldLabel=relFldMeta.fieldLabel;
                        fieldsToQuery.add(fld.relationshipName+'.'+relFldMeta.apiName);
                        break;
                    }
                }
            }
        }
        //get the data from the record
        String soqlStmt = 'select Id,'+String.join(fieldsToQuery,',')+' from '+objectApiName+' where Id=:recordId';
        System.debug('>>>>>> getTimelineItemChildData: soqlStmt = '+soqlStmt);
        List<SObject> result = Database.query(soqlStmt);
        if(!result.isEmpty()){
            TimelineDataResponse response = new TimelineDataResponse(null,result[0]);
            response.fieldMetadata=retFieldMetaData;
            return response;
        }else{
            return null;
        }
    }

    private static String getSOQLForTimeline(timeline__Timeline_Configuration__c conf,String recordId){
        String soqlStmt = 'select Id,';
        List<String> childSoqls = new List<String>();
        for(timeline__Timeline_Child_Object__c childObjConf: conf.timeline__Timeline_Child_Objects__r){
            String childSoql = '(select ';
            List<String> fieldsToQuery = childObjConf.timeline__Fields_to_Display__c.split(',');
            fieldsToQuery.add('Id');

            if(!childObjConf.timeline__Object__c.endsWith('__x') && !fieldsToQuery.contains('CreatedDate')){
                fieldsToQuery.add('CreatedDate');
            }

            if(childObjConf.Object__c.equalsIgnoreCase('Task')){
                fieldsToQuery.add('OwnerId');
                fieldsToQuery.add('WhoId');
                fieldsToQuery.add('Owner.Name');
                fieldsToQuery.add('Who.Name');
                fieldsToQuery.add('TaskSubtype');
            }
            if(childObjConf.timeline__Date_Field__c !=null && !fieldsToQuery.contains(childObjConf.timeline__Date_Field__c)){
                fieldsToQuery.add(childObjConf.timeline__Date_Field__c);
            }
            if(childObjConf.Title_Field__c !=null && !fieldsToQuery.contains(childObjConf.Title_Field__c)){
                fieldsToQuery.add(childObjConf.Title_Field__c);
            }
            childSoql += String.join(fieldsToQuery,',');
            childSoql +=' from '+childObjConf.timeline__Relationship_Name__c;
            if(childObjConf.timeline__Date_Field__c !=null){
                childSoql +=' where ' +childObjConf.timeline__Date_Field__c+ ' !=null';
            }
            childSoql +=' )';
            childSoqls.add(childSoql);
        }
        soqlStmt += String.join(childSoqls,',');
        soqlStmt += ' from '+conf.timeline__Object__c;
        soqlStmt += ' where Id=\''+String.escapeSingleQuotes(recordId)+'\'';
        return soqlStmt;
    }
}