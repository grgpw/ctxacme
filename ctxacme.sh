#!/bin/sh

CERTFILE=$1
KEYFILE=$2
CHAINFILE=$3
alias=$4
CITRIXADCIP=$5
CHAINNAME=acme-chain-$(openssl x509 -in $CHAINFILE -noout -subject_hash)

getAuthCookie () {
params="-s -i -k -H Content-Type:application/json -X POST -d {\"login\":{\"username\":\"$CITRIXADCUSER\",\"password\":\"$CITRIXADCPW\"}} https://${CITRIXADCIP}/nitro/v1/config/login"
		echo "requesting AuthCookie"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		if [ "$content" != 201 ]; then
			echo "error getting AuthCookie" $content
			exit 1
		fi
		authCookie="$(curl $params | grep Set-Cookie: | tail -1 | awk {'print $2'})"
	}

adclogout () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"logout\":{}} https://${CITRIXADCIP}/nitro/v1/config/logout"
		echo "logging out"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		if [ "$content" != 201 ]; then
			echo "error logging out" $content
		fi
	}

savensconfig () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"nsconfig\":{}}  https://${CITRIXADCIP}/nitro/v1/config/nsconfig?action=save"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "saving config"
		if [ "$content" != 200 ]; then
			echo "error saving config" $content
		fi
	}

getSSL () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X GET https://${CITRIXADCIP}/nitro/v1/config/sslcertkey/$1"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "checking sslcertkey \"$1\""
		if [ "$content" != 200 ] && [ "$content" != 599 ]; then
			echo "error checking sslcertkey" $content
		fi
	}

sendFile () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"systemfile\":{\"filename\":\"$1\",\"filelocation\":\"/nsconfig/ssl/\",\"filecontent\":\"$(cat $2 | base64 -w0)\",\"fileencoding\":\"BASE64\"}} https://${CITRIXADCIP}/nitro/v1/config/systemfile"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "sending file \"$1\""
		if [ "$content" != 201 ]; then
			echo "error sending file" $content
		fi
	}

removeFile () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X DELETE https://${CITRIXADCIP}/nitro/v1/config/systemfile/$1?args=filelocation:%2Fnsconfig%2Fssl"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "deleting file \"$1\""
	}
	
updateSSL () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"sslcertkey\":{\"certkey\":\"$1\",\"cert\":\"$2\",\"nodomaincheck\":\"true\"}} https://${CITRIXADCIP}/nitro/v1/config/sslcertkey?action=update"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "updating cert-key pair \"$1\""
		if [ "$content" != 200 ]; then
			echo "error updating cert-key pair" $content
		fi
	}

createSSL () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"sslcertkey\":{\"certkey\":\"$1\",\"cert\":\"$2\",\"key\":\"$3\"}} https://${CITRIXADCIP}/nitro/v1/config/sslcertkey"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "creating cert-key pair \"$1\""
		if [ "$content" != 201 ]; then
			echo "error creating cert-key pair" $content
		fi
	}


createSSLCA () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"sslcertkey\":{\"certkey\":\"$1\",\"cert\":\"$2\"}} https://${CITRIXADCIP}/nitro/v1/config/sslcertkey"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "creating SSL CA \"$1\""
		if [ "$content" != 201 ]; then
			echo "error creating SSL CA" $content
		fi
	}

linkSSL () {
params="-s -i -k -H Cookie:$authCookie -H Content-Type:application/json -X POST -d {\"sslcertkey\":{\"certkey\":\"$1\",\"linkcertkeyname\":\"$2\"}} https://${CITRIXADCIP}/nitro/v1/config/sslcertkey?action=link"
		content="$(curl $params | grep HTTP/1.1 | tail -1 | awk {'print $2'})"
		echo "linking cert-key pair \"$1\" with CA \"$2\""
		if [ "$content" != 200 ]; then
			echo "error linking SSL" $content
		fi
	}

getAuthCookie

getSSL "acme-$alias"
if [ "$content" = 200 ]; then
	echo "using existing cert-key pair"
	removeFile "acme-$alias.key"
	removeFile "acme-$alias.pem"
	sendFile "acme-$alias.key" "$KEYFILE"
	sendFile "acme-$alias.pem" "$CERTFILE"
	updateSSL "acme-$alias" "acme-$alias.pem"
else
	echo "creating new cert-key pair"
	sendFile "acme-$alias.key" "$KEYFILE"
	sendFile "acme-$alias.pem" "$CERTFILE"
	createSSL "acme-$alias" "acme-$alias.pem" "acme-$alias.key"
fi

getSSL "$CHAINNAME"
if [ "$content" = 200 ]; then
	echo "using existing CA and chain"
elif [ "$content" = 599 ]; then
	sendFile "$CHAINNAME.pem" "$CHAINFILE"
	createSSLCA "$CHAINNAME" "$CHAINNAME.pem"
fi
linkSSL "acme-$alias" "$CHAINNAME"

savensconfig
adclogout
