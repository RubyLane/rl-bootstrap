# rl_braintree.tcl
#
# A tcl implementation of the Braintree server side functions,
# based on those as defined in their published Ruby SDK
#
# Copyright (c) 2009-2014 Braintree, a division of PayPal, Inc.
# Copyright (c) 2015 Ruby Lane
#
# See the file LICENSE for the information on the usage and
# redistribution of this file, and for a DISCLAIMER OF ALL WARRANTIES
#

package require Tcl 8.6
package require sha1
package require tdom
package require rl_http

catch { namespace delete ::rl_braintree }
catch { rename ::rl_braintree {} }

oo::class create rl_braintree {

    variable {*}{
        config
        headers
        query_path
        query_body
    }

    constructor args { #<<<
        set config [dict merge {
            -sandbox 0 \
        } $args]
        if {[self next] ne ""} next

        dict for {k v} $config {
            if {[string index $k 0] ne "-"} {
                throw {SYNTAX GENERAL} "Invalid property name \"$k\""
            }
        }
        # Must receive the public and private key to be used
        foreach reqf {
            merchant_id
            public_key
            private_key
        } {
            if {![dict exists $config -$reqf]} {
                throw [list missing_field $reqf] "Must set -$reqf"
            }
        }

        set query_body ""

        set basic_auth [binary encode base64 "[dict get $config -public_key]:[dict get $config -private_key]"]
        set headers [dict create \
            "Authorization"     "Basic $basic_auth" \
            "X-ApiVersion"      4 \
            "Content-Type"      "application/xml; charset=utf-8" \
        ]
    }

    #>>>
    method base_merchant_path {} { #<<<
        return [file join "merchants" [dict get $config -merchant_id]]
    }

    #>>>
    method config_key { key } { #<<<
        if {[dict exists $config -$key]} {
            set val [dict get $config -$key]
        } else {
            set val ""
        }
    }

    #>>>
    method generate_client_token {} { #<<<
        my _set_query_path "client_token"

        set query_body [my _build_query_body [list version] {
            version { type integer } { t 1 }
        }]

        set token ""
		set resp [my _parse_xml_response [my _send_request]]
       
        if {[dict exists $resp value]} {
            # Debug why this is not returned already encoded.
            set token [binary encode base64 [dict get $resp value]]
        }
        set token
    }

    #>>>
	method merchant_account { action data } { #<<<
        # Full details available at https://developers.braintreepayments.com/javascript+ruby/guides/marketplace/create

		if {[dict size $data] eq 0} {
            throw [list "merchant account invalid data"] "No data"
		}
        # Field validation should be handled prior to calling this 
        # procedure.

        switch -- $action {
            create {
		        my _set_query_path [file join merchant_accounts create_via_api]
		        set query_body [my _get_merchant_query $action $data]
                set query_type POST
            }
            find {
		        my _set_query_path [file join merchant_accounts [dict get $data id]]
                set query_body ""
                set query_type get
            }
            update {
                if {![dict exists $data id]} {
                    throw [list "Invalid merchant id"] "No key \"id\" provided in dictionary"
                }
                my _set_query_path [file join merchant_accounts [dict get $data id] update_via_api]
                set query_body [my _get_merchant_query $action $data]
                set query_type PUT
            }
            default {
                throw [list "merchant account unknown action"] "Unknown action: $action"
            }
        }

        # Send request and pas back the response
        # Error handling to be managed by the caller
        set resp [my _parse_xml_response [my _send_request $query_type]]
	}

	#>>>
    method transaction { action data } { #<<<
        switch -- $action {
            sale {
		        my _set_query_path transactions
                set query_type POST
		        set query_body [my _get_transaction_query $action $data]
            }
            find {
		        my _set_query_path [file join transactions [dict get $data id]]
                set query_type GET
		        set query_body ""
            }
            default {
                throw [list "transaction unknown action"] "Unknown action: $action"
            }
        }
        set resp [my _parse_xml_response [my _send_request $query_type]]
    }

    #>>>
    
    method _build_query_body { keys script } { #<<<
        try {
            dom createDocument client doc
            $doc documentElement root
            foreach key $keys {
                dom createNodeCmd elementNode $key
            }
            dom createNodeCmd textNode t

            $root appendFromScript $script
        } on error {errmsg options} {
            throw [list "build_query_data failed"] "Unable to build query data: $errmsg"
        } on ok {} {
            $root asXML
        } finally {
            if {[info exist doc]} { $doc delete }
        }
    }

    #>>>
    method _get_api_url {} { #<<<
        if {[dict get $config -sandbox] eq 0} {
            return "api.braintreegateway.com"
        } else {
            return "api.sandbox.braintreegateway.com"
        }
    }

    #>>>
    method _get_merchant_query { action data } { #<<<
        try {
			dom createDocument merchant-account doc
			$doc documentElement root

			foreach key {
				individual email date-of-birth first-name last-name phone ssn
				address street-address locality region postal-code
				business dba_name legal-name tax-id
				funding destination descriptor account-number routing-number mobile-phone
				tos-accepted master-merchant-account-id id
			} {
				dom createNodeCmd elementNode $key
			}
			dom createNodeCmd textNode t

            $root appendFromScript {
                individual {
                    first-name 				{ t [dict get $data individual first_name] }
                    last-name 				{ t [dict get $data individual last_name] }
                    email 					{ t [dict get $data individual email] }
                    if {[dict exists $data individual phone]} {
                        phone 					{ t [dict get $data individual phone] }
                    }
                    date-of-birth 			{ t [dict get $data individual date_of_birth]}
                    if {[dict exists $data individual ssn]} {
                        ssn 				{ t [dict get $data individual ssn] }
                    }
                    address {
                        street-address 		{ t [dict get $data individual address street_address] }
                        locality 			{ t [dict get $data individual address locality] }
                        region 				{ t [dict get $data individual address region] }
                        postal-code 		{ t [dict get $data individual address postal_code] }
                    }
                }
                if {[dict exists $data business]} {
                    business {
                        legal-name          { t [dict get $data business legal_name]}
                        if {[dict exists $data business dba_name]} {
                            # optional
                            dba_name        { t [dict get $data business dba_name] }
                        }
                        tax-id              { t [dict get $data business tax_id] }
                    }
                    if {[dict exists $data business address]} {
                        # If provided, all fields required
                        street-address 		{ t [dict get $data business address street_address] }
                        locality 			{ t [dict get $data business address locality] }
                        region 				{ t [dict get $data business address region] }
                        postal-code 		{ t [dict get $data business address postal_code] }
                    }
                }
                funding {
                    if {[dict exists $data funding descriptor]} {
                        descriptor          { t [dict get $data funding descriptor] }
                    }
                    destination             { t [dict get $data funding destination] }
                    switch -- [dict get $data funding destination] {
                        bank {
                            account-number  { t [dict get $data funding account_number] }
                            routing-number  { t [dict get $data funding routing_number] }
                        }
                        mobile_phone {
                            mobile-phone    { t [dict get $data funding mobile_phone]}
                        }
                        email {
                            email           { t [dict get $data funding email] }
                        }
                        default {
                            # Throw error - unknown funding option
                        }
                    }
                }
				if { $action eq "create" } {
					tos-accepted 				{type boolean} { t "true" }
					master-merchant-account-id 	{ t [dict get $data master_merchant_account_id] }
                    if {[dict exists $data id] && [dict get $data id] ne ""} {
					    id 							{ t [dict get $data id] }
                    }
				}
            }
        } on error {errmsg options} {
            throw [list "merchant account query error"] "Problem formatting xml query: $errmsg"
        } on ok {} {
			$root asXML
        } finally {
			if {[info exists doc]} {
				$doc delete
			}
        }
    }

    #>>>
    method _get_transaction_query { action data } { #<<<
        try {
			dom createDocument transaction doc
			$doc documentElement root

			foreach key {
				amount order_id  merchant-account-id payment-method-nonce
				customer first-name last-name company phone fax website email
                billing street-address extended-address locality region postal-code country-code-alpha2
                shipping
                options submit-for-settlement
                channel
                type service-fee-amount
                custom-fields
			} {
				dom createNodeCmd elementNode $key
			}
			dom createNodeCmd textNode t

            $root appendFromScript {
                type                        { t "sale" }
                merchant-account-id         { t [dict get $data merchant_account_id] }
                amount                      { t [dict get $data amount] }
                payment-method-nonce        { t [dict get $data payment_method_nonce] }
                service-fee-amount          { t [dict get $data service_fee_amount] }
                if {[dict exists $data order_id]} { order_id { t [dict get $data order_id]} }
                foreach { key subkeys } {
                    customer {
                        first_name
                        last_name
                        company
                        phone
                        fax
                        website
                        email
                    }
                    billing {
                        first_name
                        last_name
                        company
                        street_address
                        extended_address
                        locality
                        region
                        postal_code
                        country_code_alpha2
                    }
                    shipping {
                        first_name
                        last_name
                        company
                        street_address
                        extended_address
                        locality
                        region
                        postal_code
                        country_code_alpha2
                    }
                } {
                    if {[dict exists $data $key]} {
                        ${key} {
                            foreach k $subkeys {
                                if {[dict exists $data ${key} $k]} {
                                    [string map [list _ -] $k] { t [dict get $data ${key} $k]} 
                                }
                            }
                        }
                    }
                }
                if {[dict exists $data channel]} { channel { t [dict get $data channel]} }
                if {[dict exists $data options]} {
                    options {
                        submit-for-settlement       {type boolean} { t "true" }
                    }
                }
            }
        } on error {errmsg options} {
            throw [list "transaction query error"] "Problem formatting xml query: $errmsg"
        } on ok {} {
			$root asXML
        } finally {
			if {[info exists doc]} {
				$doc delete
			}
        }
    }

    #>>>
	method _parse_node { n } { #<<<
		# This is quite simplistic and does not
		# cater for all cases. 
		# Where repeated elements, at the same level
		# are not nested structures, this is fine
		set dat [dict create]
	    
        while {[$n hasChildNodes]} {
			set child [$n firstChild]
			set node_name [$child nodeName]
			if {[llength [$child childNodes]] >= 1 && [[$child firstChild] nodeType] ne "TEXT_NODE"} {
				# dict set dat $node_name [my _parse_node $child]
				set cn [my _parse_node $child]
				if {[dict exists $dat $node_name]} {
					dict set dat $node_name [list {*}[dict get $dat $node_name] {*}$cn]
				} else {
					dict set dat $node_name $cn
				}
			} elseif {[llength [$child childNodes]] eq 0} {
                # puts "Empty node: $node_name"
				dict set dat $node_name {}
			} else {
                # puts "Text node: $node_name"
				if {[dict exists $dat $node_name]} {
                    # puts "appending to $node_name: [$child asText]"
					dict set dat $node_name [list {*}[dict get $dat $node_name] [$child asText]]
				} else {
                    # puts "set key $node_name to [$child asText]"
					dict set dat $node_name [$child asText]
				}
			}
			$n removeChild $child
		}
		return $dat
    }

	#>>>
	method _parse_xml_response { resp } { #<<<
        # puts "rl_braintree _parse_xml_reponse: check resp: [string trim $resp]"
		if {[string length [string trim $resp]] < 1} {
			# Nothing to parse
			return $resp
		}
		# Parse XML response from Braintree
		# Check if the xml response starts with
		# <?xml ... ?> - strip it if it does before
		# parsing with tdom
		if {[regexp -indices {(<\?xml.*\?>)} $resp match]} {
			set start [lindex $match 0]
			set end [lindex $match 1]
			set resp [string replace $resp $start $end ""]
		}

		set info [dict create]
		try {
			dom parse $resp doc
			$doc documentElement root
			return [my _parse_node $root]
		} on error {errmsg options} {
            throw [list "parse xml error"] "Problem parsing response from Braintree: $errmsg"
        } finally {
			if {[info exists doc]} {
				$doc delete
			}
		}
	}

	#>>>
    method _send_request { { type POST }} { #<<<
        # puts "Sending Braintree request ($type) :\nurl: $query_path\nheaders: $headers\ndata: $query_body "
        try {
            rl_http create h [string toupper $type] https://$query_path \
                -data [encoding convertto utf-8 $query_body] \
                   -headers $headers \
                   -accept "application/xml"
        } on error {errmsg options} {
            throw [list "send request error"] "Problem sending request: $errmsg"
        } on ok {} {
            # [h code] returns the response html code, e.g 200, etc
            set resp [h body]
        } finally {
            if {[info object isa object h]} { h destroy }
        }
    }

    #>>>
    method _set_query_path action { #<<<
        # This only accomodates Braintree Marketplace, at this point
        set query_path [file join [my _get_api_url] [my base_merchant_path] $action]
    }

    #>>>
}

# vim: foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4 ft=tcl
