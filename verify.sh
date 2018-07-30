if [ -z "$(which az)" ]; then
    echo "Azure CLI 2.0+ must be installed and on path." 1>&2
    exit 1
fi


# Check Azure CLI version
expectedCliVersion="2.0.41"
actualCliVersion=$(az --version | grep azure-cli | sed 's/.*(\(.*\))/\1/')

expectedPieces=($(echo $expectedCliVersion | tr "." "\n"))
actualPieces=($(echo $actualCliVersion | tr "." "\n"))
for index in "${!expectedPieces[@]}"
do
    actual=${actualPieces[index]}
    if [ "${expectedPieces[index]}" -gt "${actual}" ]; then
        echo "Azure CLI version ${expectedCliVersion} required. Version ${actualCliVersion} is installed." 2>&1
        exit 1        
    elif [ "${expectedPieces[index]}" -lt "${actual}" ]; then
        # This version is greater than expected. No need to compare more minor numbers.
        break
    fi
done


if [ -z "$(which kubectl)" ]; then
    echo "kubectl must be installed and on path. Run \"az aks install-cli\" to install." 1>&2
    exit 1
fi

if [ -z "$(which psql)" ]; then
    echo "psql must be installed and on path." 1>&2
    exit 1
fi
