component {

    variables.service = 'route53';

    public any function init(
        required any api,
        required struct settings
    ) {
        variables.api = arguments.api;
        variables.utils = variables.api.getUtils();
        variables.apiVersion = arguments.settings.apiVersion;
        return this;
    }

    /**
    * Search all hosted records for a name that contains the provided search string.
    * @searchString Required string. Returns records with names that contain this string.
    * Use a blank string to get all hosted zones above the 100 limit using listHostedZones().
    * @getExtendedDetails Optional Boolean. If set to true, makes an additional call to
    * listResourceRecordSets() to include all resource record sets for each matched hosted zone.
    * @extendedDetailsTypeList Option String. Comma separated list of record types to be
    * returned (e.g. A,AAAA,CAA,CNAME,MX,NAPTR,NS,PTR,SOA,SPF,SRV,TXT)
    * @maximumCalls Optional number. This limits the total number of calls to be aggregated.
    * Caution: If you are searching a large number of records, you need to ensure your request
    * timeout is sufficient. getExtendedDetails adds an additional call per each record.
    */
    public any function searchHostedZones(
        required String searchString,
        Boolean getExtendedDetails = false,
        String extendedDetailsTypeList = '',
        Numeric maximumCalls = 15
    ) {
        var endReached = false;
        var currentCalls = 0;
        var nextMarker = '';
        var returnResults = [ ];
        // Define local vars for inside the array filter
        var searchFor = arguments.searchString;
        var extended = arguments.getExtendedDetails;
        var includeTypeList = arguments.extendedDetailsTypeList;

        while ( !endReached ) {
            currentCalls++;
            if ( currentCalls > arguments.maximumCalls ) {
                endReached = true;
                break;
            }
            var zoneResults = listHostedZones( nextMarker );
            for( var i=1; i <= arrayLen(zoneResults.data.HostedZones); i++  ) {

            }
            zoneResults.data.HostedZones.filter( function( item ) {
                if ( item.Name CONTAINS searchFor ) {
                    if ( extended ) {
                        var rrsetResults = listResourceRecordSets( item.Id, includeTypeList );
                        if ( !isNull( rrsetResults.data ) ) {
                            structAppend( item, { 'ResourceRecordSets': rrsetResults.data.ResourceRecordSets } );
                            structAppend( item, { 'ResourceRecordSetsIsTruncated': rrsetResults.data.IsTruncated } );
                        }
                    }
                    arrayAppend( returnResults, item );
                }
                return item.Name CONTAINS searchFor;
            } );
            if ( !isNull( zoneResults.data.nextMarker ) ) {
                nextMarker = zoneResults.data.nextMarker;
            } else {
                endReached = true;
            }
        }
        return returnResults;
    }

    /**
    * Create a new hosted zone
    * https://docs.aws.amazon.com/Route53/latest/APIReference/API_CreateHostedZone.html
    * @name Required String. The name of the domain. Specify a fully qualified domain name, for example domain.com
    * @callerReference Optional String. A unique string that identifies the request and that allows failed CreateHostedZone
    * requests to be retried without the risk of executing the operation twice.
    * @delegationSetId Optional String. If you want to associate a reusable delegation set with this hosted zone, the ID
    * that Amazon Route 53 assigned to the reusable delegation set when you created it.
    * @privateZone Optional Boolean. If true, the hosted zone will be private. If false, the hosted zone will be public.
    * @vpcId Optional String. You can only specify VPCId for private zones.
    * @vpcRegion Optional String. You can only specify VPCId for private zones.
    */
    public any function createHostedZone(
        required String name,
        String callerReference = createUUID(),
        String delegationSetId = '',
        Boolean privateZone = false,
        String vpcId = '',
        String vpcRegion = ''
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var delegationId = replaceNoCase(
            arguments.delegationSetId,
            '/delegationset/',
            '',
            'all'
        );
        var xmlRequestBody = '<?xml version="1.0" encoding="UTF-8"?>
		<CreateHostedZoneRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
		<CallerReference>#arguments.callerReference#</CallerReference>';
        if ( len( trim( arguments.delegationSetId ) ) ) {
            xmlRequestBody = xmlRequestBody & '<DelegationSetId>#delegationId#</DelegationSetId>';
        }
        xmlRequestBody = xmlRequestBody & '<HostedZoneConfig><PrivateZone>#arguments.privateZone#</PrivateZone></HostedZoneConfig>';
        xmlRequestBody = xmlRequestBody & '<Name>#arguments.name#</Name>';
        if ( len( trim( arguments.vpcId ) ) && len( trim( arguments.vpcRegion ) ) ) {
            xmlRequestBody = xmlRequestBody & '<VPC><VPCId>#arguments.vpcId#</VPCId><VPCRegion>#arguments.vpcRegion#</VPCRegion></VPC>';
        }
        xmlRequestBody = xmlRequestBody & '</CreateHostedZoneRequest>';
        var apiResponse = apiCall(
            requestSettings,
            'POST',
            '/' & variables.apiVersion & '/hostedzone/',
            { },
            { },
            local.xmlRequestBody
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    /**
    * Change Resource Record Sets
    * https://docs.aws.amazon.com/Route53/latest/APIReference/API_ChangeResourceRecordSets.html
    * @hostedZoneId Required string. The hosted zone ID to be changed.
    * This function accepts hosted zone IDs with or without /hostedzone/ included.
    * @xmlRequestBody XML payload used to create the hosted zone. See AWS docs for request syntax
    * Hint: You can pass in your own XML request body or you can use getChangeBatchItemXmlFromStruct()
    * to convert a struct to HTML then get the complete XML request body with getChangeBatchXml()
    */
    public any function changeResourceRecordSets(
        required String hostedZoneId,
        required String xmlRequestBody
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var zoneId = replaceNoCase(
            arguments.hostedZoneId,
            '/hostedzone/',
            '',
            'all'
        );
        var apiResponse = apiCall(
            requestSettings,
            'POST',
            '/' & variables.apiVersion & '/hostedzone/' & zoneId & '/rrset/',
            { },
            { },
            arguments.xmlRequestBody
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    /**
    * Delete a hosted zone
    * @hostedZoneId Required string. The hosted zone ID to be deleted.
    * This function accepts hosted zone IDs with or without /hostedzone/ included.
    * Caution: All resource record sets will be purged, then the hosted zone will be deleted.
    */
    public any function deleteHostedZone(
        required String hostedZoneId
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var zoneId = replaceNoCase(
            arguments.hostedZoneId,
            '/hostedzone/',
            '',
            'all'
        );
        // To be able to delete a hosted zone, all resource records must first be purged
        purgeAllHostedZoneRecordsById( zoneId );
        var apiResponse = apiCall(
            requestSettings,
            'DELETE',
            '/' & variables.apiVersion & '/hostedzone/' & zoneId,
            { }
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    /**
    * Deletes all resource records for a hosted zone that can be deleted (A,AAAA,CAA,CNAME,MX,NAPTR,PTR,SPF,SRV,TXT)
    * @hostedZoneId Required string. The hosted zone ID to be deleted.
    * This function accepts hosted zone IDs with or without /hostedzone/ included.
    */
    public any function purgeAllHostedZoneRecordsById(
        required String hostedZoneId
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var zoneId = replaceNoCase(
            arguments.hostedZoneId,
            '/hostedzone/',
            '',
            'all'
        );
        // Get all records that can be deleted (SOA, NS cannot be deleted)
        var zoneRecords = listResourceRecordSets( zoneId, 'A,AAAA,CAA,CNAME,MX,NAPTR,PTR,SPF,SRV,TXT' );
        if (
            !isNull( zoneRecords.data.ResourceRecordSets )
            && isArray( zoneRecords.data.ResourceRecordSets )
            && arrayLen( zoneRecords.data.ResourceRecordSets )
        ) {
            var itemXml = '';
            for ( var i = 1; i <= arrayLen( zoneRecords.data.ResourceRecordSets ); i++ ) {
                itemXml = itemXml & getChangeBatchItemXmlFromStruct(
                    zoneRecords.data.ResourceRecordSets[ i ],
                    'DELETE'
                );
                var changeRequestXml = getChangeBatchXml( itemXml );
                changeResourceRecordSets( zoneId, changeRequestXml );
            }
            return { 'result': 'Deleted #arrayLen( zoneRecords.data.ResourceRecordSets )# records' };
        } else {
            return { 'result': 'No records to delete' };
        }
        return zoneRecords;
    }

    /**
    * List Resource Record Sets
    * @hostedZoneId Required string. The hosted zone ID for requested record sets.
    * This function accepts hosted zone IDs with or without /hostedzone/ included.
    * @includeRecordTypeList Optional string. Comma separated list of record types to be
    * returned (e.g. A,AAAA,CAA,CNAME,MX,NAPTR,NS,PTR,SOA,SPF,SRV,TXT). A blank string
    * returns all types.
    */
    public any function listResourceRecordSets(
        required String hostedZoneId,
        String includeRecordTypeList = ''
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var zoneId = replaceNoCase(
            arguments.hostedZoneId,
            '/hostedzone/',
            '',
            'all'
        );
        var apiResponse = apiCall(
            requestSettings,
            'GET',
            '/' & variables.apiVersion & '/hostedzone/' & zoneId & '/rrset',
            { }
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
            if ( listLen( arguments.includeRecordTypeList ) ) {
                var matchedRecordSets = [ ];
                for ( rrsetItem in apiResponse.data.resourceRecordSets ) {
                    if ( listFindNoCase( arguments.includeRecordTypeList, rrsetItem.Type ) ) {
                        arrayAppend( matchedRecordSets, rrsetItem );
                    }
                }
                // Replace with matched record sets based on the includeRecordTypeList
                apiResponse.data.resourceRecordSets = matchedRecordSets;
            }
        }
        return apiResponse;
    }

    /**
    * Get a hosted zone by the zone Id
    * @hostedZoneId Required string. The hosted zone ID to get.
    * This function accepts hosted zone IDs with or without /hostedzone/ included.
    */
    public any function getHostedZone(
        required String hostedZoneId
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var zoneId = replaceNoCase(
            arguments.hostedZoneId,
            '/hostedzone/',
            '',
            'all'
        );
        var apiResponse = apiCall(
            requestSettings,
            'GET',
            '/' & variables.apiVersion & '/hostedzone/' & zoneId,
            { }
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    /**
    * Returns hosted zones. Max records returned in 100. Use nextMarker from previous request
    * to get the nxt set of records. IsTruncated will equal false on the last record set.
    * @nextMarker Optional string. Marker from the previous request if results are truncated.
    */
    public any function listHostedZones(
        String nextMarker
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var urlParams = { };
        if ( !isNull( arguments.nextMarker ) && len( trim( arguments.nextMarker ) ) ) {
            structAppend( urlParams, { 'marker': arguments.nextMarker } );
        }
        var apiResponse = apiCall(
            requestSettings,
            'GET',
            '/' & variables.apiVersion & '/hostedzone/',
            urlParams
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    /**
    * Creates the XML request body needed for the ChangeResourceRecordSets function.
    * https://docs.aws.amazon.com/Route53/latest/APIReference/API_ChangeResourceRecordSets.html
    * Use the getChangeBatchItemXmlFromStruct to generate the <change></change> XML from a struct
    * @changeItemsXmlString Required String. The XML snippet with <change></change> element(s)
    * for CREATE|DELETE|UPSERT actions.
    */
    public function getChangeBatchXml(
        Required String changeItemsXmlString
    ) {
        return '<?xml version="1.0" encoding="UTF-8"?>
		<ChangeResourceRecordSetsRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
		   <ChangeBatch>
			  <Changes>
				 #arguments.changeItemsXmlString#
			  </Changes>
			  <Comment>string</Comment>
		   </ChangeBatch>
		</ChangeResourceRecordSetsRequest>';
    }

    /**
    * Converts a struct to XML snippet for a batch item CREATE|DELETE|UPSERT action.
    * https://docs.aws.amazon.com/Route53/latest/APIReference/API_ChangeResourceRecordSets.html
    * @record Required Struct. Hosted zone resource record structure. Can be passed in from other
    * functions or it can be crafted manually. The DELETE action requires all existing values
    * for a successful delete operation. UPSERT: If a resource record set does not already exist,
    * AWS creates it. If a resource set does exist, Route 53 updates it with the values in the request.
    * @action Required String. Valid values CREATE, DELETE, or UPSERT.
    */
    public function getChangeBatchItemXmlFromStruct(
        required Struct resourceRecord,
        required String action
    ) {
        if( arguments.action != 'CREATE' && arguments.action != 'UPSERT' && arguments.action != 'DELETE' ) {
            throw( 'Invalid action (#arguments.action#). Action must be CREATE, UPSERT, or DELETE.' );
        }
        if( !structCount( arguments.resourceRecord ) ) {
            throw( 'The resourceRecord struct must not be empty.' );
        }
        savecontent variable="changeItemXml" {
            writeOutput( '<Change>' );
            writeOutput( '<Action>#arguments.action#</Action>' );
            writeOutput( '<ResourceRecordSet>' );
            if ( !isNull( resourceRecord.AliasTarget ) ) {
                writeOutput( '<AliasTarget>' );
                if ( !isNull( resourceRecord.AliasTarget.DNSName ) ) {
                    writeOutput( '<DNSName>#resourceRecord.GeoLocation.DNSName#</DNSName>' );
                }
                if ( !isNull( resourceRecord.AliasTarget.EvaluateTargetHealth ) ) {
                    writeOutput(
                        '<EvaluateTargetHealth>#resourceRecord.GeoLocation.EvaluateTargetHealth#</EvaluateTargetHealth>'
                    );
                }
                if ( !isNull( resourceRecord.AliasTarget.HostedZoneId ) ) {
                    writeOutput( '<HostedZoneId>#resourceRecord.GeoLocation.HostedZoneId#</HostedZoneId>' );
                }
                writeOutput( '</AliasTarget>' );
            }
            if ( !isNull( resourceRecord.Failover ) ) {
                writeOutput( '<Failover>#resourceRecord.Failover#</Failover>' );
            }
            if ( !isNull( resourceRecord.GeoLocation ) ) {
                writeOutput( '<GeoLocation>' );
                if ( !isNull( resourceRecord.GeoLocation.ContinentCode ) ) {
                    writeOutput( '<ContinentCode>#resourceRecord.GeoLocation.ContinentCode#</ContinentCode>' );
                }
                if ( !isNull( resourceRecord.GeoLocation.CountryCode ) ) {
                    writeOutput( '<CountryCode>#resourceRecord.GeoLocation.CountryCode#</CountryCode>' );
                }
                if ( !isNull( resourceRecord.GeoLocation.SubdivisionCode ) ) {
                    writeOutput( '<SubdivisionCode>#resourceRecord.GeoLocation.SubdivisionCode#</SubdivisionCode>' );
                }
                writeOutput( '</GeoLocation>' );
            }
            if ( !isNull( resourceRecord.HealthCheckId ) ) {
                writeOutput( '<HealthCheckId>#resourceRecord.HealthCheckId#</HealthCheckId>' );
            }
            if ( !isNull( resourceRecord.MultiValueAnswer ) ) {
                writeOutput( '<MultiValueAnswer>#resourceRecord.MultiValueAnswer#</MultiValueAnswer>' );
            }
            if ( !isNull( resourceRecord.Name ) ) {
                writeOutput( '<Name>#resourceRecord.Name#</Name>' );
            }
            if ( !isNull( resourceRecord.Region ) ) {
                writeOutput( '<Region>#resourceRecord.Region#</Region>' );
            }
            if ( !isNull( resourceRecord.ResourceRecords ) ) {
                writeOutput( '<ResourceRecords>' );
                if ( isArray( resourceRecord.ResourceRecords ) ) {
                    for ( item in resourceRecord.ResourceRecords ) {
                        writeOutput( '<ResourceRecord><Value>#item.value#</Value></ResourceRecord>' );
                    }
                } else if ( !isNull(resourceRecord.ResourceRecords.ResourceRecord) 
                    && isStruct( resourceRecord.ResourceRecords.ResourceRecord ) ) {
                    writeOutput(
                        '<ResourceRecord><Value>#resourceRecord.ResourceRecords.ResourceRecord.value#</Value></ResourceRecord>'
                    );
                }
                writeOutput( '</ResourceRecords>' );
            }
            if ( !isNull( resourceRecord.SetIdentifier ) ) {
                writeOutput( '<SetIdentifier>#resourceRecord.SetIdentifier#</SetIdentifier>' );
            }
            if ( !isNull( resourceRecord.TrafficPolicyInstanceId ) ) {
                writeOutput( '<TrafficPolicyInstanceId>#resourceRecord.TrafficPolicyInstanceId#</TrafficPolicyInstanceId>' );
            }
            if ( !isNull( resourceRecord.TTL ) ) {
                writeOutput( '<TTL>#resourceRecord.TTL#</TTL>' );
            }
            if ( !isNull( resourceRecord.Type ) ) {
                writeOutput( '<Type>#resourceRecord.Type#</Type>' );
            }
            if ( !isNull( resourceRecord.Weight ) ) {
                writeOutput( '<Weight>#resourceRecord.Weight#</Weight>' );
            }
            writeOutput( '</ResourceRecordSet>' );
            writeOutput( '</Change>' );
        };
        return changeItemXml;
    }

    /**
     * Retrieves a list of the reusable delegation sets that are associated with the current AWS account.
     * https://docs.aws.amazon.com/Route53/latest/APIReference/API_ListReusableDelegationSets.html
     * @getLimit Optional Boolean. Appends getReusableDelegationSetLimit() for each delegation set.
     * @nextMarker Optional String. Marker from the previous request if results are truncated.
     */
    public any function listReusableDelegationSets(
        Boolean getLimit = false,
        String nextMarker
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var urlParams = { };
        if ( !isNull( arguments.nextMarker ) && len( trim( arguments.nextMarker ) ) ) {
            structAppend( urlParams, { 'marker': arguments.nextMarker } );
        }
        var apiResponse = apiCall(
            requestSettings,
            'GET',
            '/' & variables.apiVersion & '/delegationset/',
            urlParams
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
            if ( arguments.getLimit && !isNull( apiResponse.data.DelegationSets.DelegationSet.Id ) ) {
                apiResponse[ 'limit' ] = getReusableDelegationSetLimit(
                    apiResponse.data.DelegationSets.DelegationSet.Id
                ).data;
            }
        }
        return apiResponse;
    }

    /**
     * Creates a delegation set that can be reused by multiple hosted zones that were created by the same AWS account.
     * https://docs.aws.amazon.com/Route53/latest/APIReference/API_CreateReusableDelegationSet.html
     * @hostedZoneId Required string. The hosted zone ID to be changed.
     * This function accepts hosted zone IDs with or without /hostedzone/ included.
     *   Optional String. Marker from the previous request if results are truncated.
     */
    public any function createReusableDelegationSet(
        Required String hostedZoneId,
        String callerReference = createUUID()
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var zoneId = replaceNoCase(
            arguments.hostedZoneId,
            '/hostedzone/',
            '',
            'all'
        );
        var xmlBodyResponse = '<?xml version="1.0" encoding="UTF-8"?>
		<CreateReusableDelegationSetRequest xmlns="https://route53.amazonaws.com/doc/2013-04-01/">
		   <CallerReference>#arguments.CallerReference#</CallerReference>
		   <HostedZoneId>#local.zoneId#</HostedZoneId>
		</CreateReusableDelegationSetRequest>';
        var apiResponse = apiCall(
            requestSettings,
            'POST',
            '/' & variables.apiVersion & '/delegationset',
            { },
            { },
            xmlBodyResponse
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    public any function getReusableDelegationSet(
        Required String delegationSetId,
        Boolean getLimit = true
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var delegationId = replaceNoCase(
            arguments.delegationSetId,
            '/delegationset/',
            '',
            'all'
        );
        var apiResponse = apiCall(
            requestSettings,
            'GET',
            '/' & variables.apiVersion & '/delegationset/#delegationId#',
            { }
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
            if ( arguments.getLimit && !isNull( apiResponse.data.DelegationSet.Id ) ) {
                apiResponse[ 'limit' ] = getReusableDelegationSetLimit( apiResponse.data.DelegationSet.Id ).data;
            }
        }
        return apiResponse;
    }

    public any function getReusableDelegationSetLimit(
        Required String delegationSetId
    ) {
        var requestSettings = api.resolveRequestSettings( argumentCollection = arguments );
        var delegationId = replaceNoCase(
            arguments.delegationSetId,
            '/delegationset/',
            '',
            'all'
        );
        var apiResponse = apiCall(
            requestSettings,
            'GET',
            '/' & variables.apiVersion & '/reusabledelegationsetlimit/#delegationId#/MAX_ZONES_BY_REUSABLE_DELEGATION_SET',
            { }
        );
        if ( apiResponse.statusCode == 200 ) {
            apiResponse[ 'data' ] = utils.parseXmlDocument( apiResponse.rawData );
        }
        return apiResponse;
    }

    // private

    private string function getHost() {
        return variables.service & '.amazonaws.com';
    }

    private any function apiCall(
        required struct requestSettings,
        string httpMethod = 'GET',
        string path = '/',
        struct queryParams = { },
        struct headers = { },
        any payload = ''
    ) {
        var host = getHost( requestSettings.region );
        structAppend( queryParams, { 'Version': variables.apiVersion }, false );

        // Route53 must be use us-east-1
        return api.call(
            variables.service,
            host,
            'us-east-1',
            httpMethod,
            path,
            queryParams,
            headers,
            payload,
            requestSettings.awsCredentials
        );
    }

}
