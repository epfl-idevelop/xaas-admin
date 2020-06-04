﻿<#
USAGES:
    xaas-billing.ps1  -targetEnv prod|test|dev -service <service> -action extractData
    xaas-billing.ps1  -targetEnv prod|test|dev -service <service> -action billing [-redoBill <billReferenc>] [-sendToCopernic] [-copernicRealMode]
    
#>
<#
    BUT 		: Script permettant de faire 2 choses :
                    1. Générer les données (utilisation) nécessaires à la facturation d'un service donné.
                        Cette action doit être entreprise à la fin d'un mois donné
                    2. Générer les factures pour un service donné et ajouter les informations dans Copernic
                        Cette action doit être entreprise au début du mois suivant. Même si on aurait pu le 
                        faire dernier jour du mois précédent le soir, c'est plus correct de faire ceci après
                        coup, le mois suivant. 

	DATE 	: Avril 2020
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.00

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.  
      
    
    PREREQUIS :
    

#>
param([string]$targetEnv, 
      [string]$service, 
      [string]$action,
      [string]$redoBill,
      [switch]$sendToCopernic,
      [switch]$copernicRealMode)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MySQL.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Billing.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "BillingS3Bucket.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ITServices.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "CopernicAPI.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configBilling = [ConfigReader]::New("config-billing.json")

##### Constantes

# Montant minimmum à partir duquel on facture
$global:BILLING_MIN_MOUNT_CHF = 5
# Nombre de jours pendant lesquels on garde les fichiers PDF générés avant de les effacer.
$global:BILLING_KEEP_PDF_NB_DAYS = 30

# Actions possibles par le script
$global:ACTION_EXTRACT_DATA = "extractData"
$global:ACTION_BILLING      = "billing"

<#
	-------------------------------------------------------------------------------------
    BUT : Prend le contenu de $valToReplace et cherche la chaine de caractère {{<key>}}
            dans $str puis la remplace par la valeur associée

	IN  : $str				-> Chaîne de caractères dans laquelle effectuer les remplacements
	IN  : $valToReplace     -> Dictionnaaire avec en clef la chaine de caractères
								à remplacer dans le code JSON (qui sera mise entre {{ et }} dans
								la chaîne de caractères). 
	
	RET : La chaine de caractères mise à jour
#>
function replaceInString([string]$str, [System.Collections.IDictionary] $valToReplace)
{
    # Parcours des remplacements à faire
    foreach($search in $valToReplace.Keys)
    {
        $strToSearch = "{{$($search)}}"

        $replaceWith = $valToReplace.Item($search)

        # Si on a des retours à la ligne dans la valeur à remplacer
        if($replaceWith -like "*\n*")
        {
            # On met le tout dans des paragraphes pour que le HTML soit généré correctement
            $replaceWith = "<p>{0}</p>" -f ($replaceWith -replace "\\n", "</p><p>")
        }

        $str = $str -replace  $strToSearch, $replaceWith
    }
    return $str
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie la représentation MM.YYYY pour le mois et l'année passés
    
    IN  : $month            -> Mois de facturation
    IN  : $year             -> année de facturation

    RET : Représentation MM.YYYY de ce qui est passé
#>
function getItemDateMonthYear([int]$month, [int]$year)
{
    $monthStr = $month.toString()
    if($month -lt 10)
    {
        # Ajout du 0 initial pour la requête de recherche 
        $monthStr = "0{0}" -f $monthStr
    }
    return ("{0}.{1}" -f $monthStr, $year)
}

<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

	IN  : $notifications-> Dictionnaire
	IN  : $targetEnv	-> Environnement courant
#>
function handleNotifications([System.Collections.IDictionary] $notifications, [string]$targetEnv)
{

	# Parcours des catégories de notifications
	ForEach($notif in $notifications.Keys)
	{
		# S'il y a des notifications de ce type
		if($notifications[$notif].count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications[$notif] | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{
				# ---------------------------------------
				# Préfixes de machine non trouvés
				'copernicBillNotSent'
				{
					$valToReplace.entityList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Entity bill not sent to Copernic"
					$templateName = "copernic-bill-send-error"
				}


				default
				{
					# Passage à l'itération suivante de la boucle
					$logHistory.addWarningAndDisplay(("Notification '{0}' not handled in code !" -f $notif))
					continue
				}

			}# FIN EN FONCTION de la notif

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			$notificationMail.send($mailSubject, $templateName, $valToReplace)

		} # FIN S'il y a des notifications pour la catégorie courante

	}# FIN BOUCLE de parcours des catégories de notifications
}




# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-billing', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # Si on doit ajouter dans Copernic
    if($sendToCopernic)
    {
        if($copernicRealMode)
        {
            $logHistory.addLineAndDisplay("Data will be added in Copernic for REAL !!")
            $execMode = "REAL"
        }
        else
        {
            $logHistory.addLineAndDisplay("Data WON'T be added in Copernic because script is executed in SIMULATION MODE !!")
            $execMode = "SIMU"
        }
    }

    # Objet pour pouvoir envoyer des mails de notification
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, "None")

    # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()
    $counters.add('entityProcessed', '# Entity processed')
    $counters.add('billDone', '# Bill done')
    $counters.add('billSkippedToLow', '# Bill skipped (amount to low)')
    $counters.add('billSkippedNothing', '# Bill skipped (nothing to bill)')
    $counters.add('billCanceled', '# Bill canceled')
    $counters.add('billSentToCopernic', '# Bill sent to Copernic')
    $counters.add('billCopernicError', '# Bill not sent to Copernic because of an error')
    $counters.add('PDFGenerated', '# PDF generated')
    $counters.add('PDFOldCleaned', '# Old PDF cleaned')
    
    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
    $notifications=@{
        copernicBillError = @()
    }
    

    # Pour accéder à la base de données
    $mysql = [MySQL]::new($configBilling.getConfigValue($targetEnv, "db", "host"), `
                          $configBilling.getConfigValue($targetEnv, "db", "dbName"), `
                          $configBilling.getConfigValue($targetEnv, "db", "user"), `
                          $configBilling.getConfigValue($targetEnv, "db", "password"), `
                          $global:BINARY_FOLDER, `
                          $configBilling.getConfigValue($targetEnv, "db", "port"))

    $ldap = [EPFLLDAP]::new()

    # Objet pour lire les informations sur le services IT
    $itServices = [ITServices]::new()

    # On prend la liste correspondant à l'environnement sur lequel on se trouve
    $itServicesList = $itServices.getServiceList($targetEnv)

    # Fichier JSON contenant les détails du service que l'on veut facturer    
    $serviceBillingInfosFile = ([IO.Path]::Combine("$PSScriptRoot", "data", "billing", $service.ToLower(), "service.json"))

    if(!(Test-Path -path $serviceBillingInfosFile))
    {
        Throw ("Service file ({0}) for '{1}' not found. Please create it from 'config-sample.json' file." -f $serviceBillingInfosFile, $service)
    }

    # Chargement des informations (On spécifie UTF8 sinon les caractères spéciaux ne sont pas bien interprétés)
    $serviceBillingInfos = Get-Content -Path $serviceBillingInfosFile -Encoding:UTF8 | ConvertFrom-Json


    # Création de l'objet pour faire les opérations pour le service donné. On le créée d'une manière dynamique en utilisant la bonne classe
    # en fonction du type de service à facturer
    $expression = '$billingObject = [{0}]::new($mysql, $ldap, $itServicesList, $serviceBillingInfos, $targetEnv)' -f $serviceBillingInfos.billingClassName
    Invoke-expression $expression

    # Pour accéder à Copernic
    $copernic = [CopernicAPI]::new($configBilling.getConfigValue($targetEnv, "copernic", "server"), `
                                   $configBilling.getConfigValue($targetEnv, "copernic", "username"), `
                                   $configBilling.getConfigValue($targetEnv, "copernic", "password"))

    # En fonction de l'action demandée
    switch($action)
    {
        ########################################################################
        ##             GENERATION DES DONNEES DE FACTURATION                  ##
        $global:ACTION_EXTRACT_DATA
        {
            $month = [int](Get-Date -Format "MM")
            $year = [int](Get-Date -Format "yyyy")

            # Extraction des données pour les mettre dans la table où tout est formaté la même chose
            $billingObject.extractData($month, $year)


            # SI on doit reset une facture pour l'émettre à nouveau
            if($redoBill -ne "")
            {
                $logHistory.addLineAndDisplay(("Canceling bill with reference {0}" -f $redoBill))
                $billingObject.cancelBill($redoBill)
                $counters.inc('billCanceled')
            }
        }

        ########################################################################
        ##                   GENERATION DES FACTURES                          ##
        $global:ACTION_BILLING
        {
            # Templates pour la génération de factures
            $billingTemplate = Get-content -path $global:XAAS_BILLING_ROOT_DOCUMENT_TEMPLATE -Encoding UTF8
            $billingItemTemplate = Get-content -path $global:XAAS_BILLING_ITEM_DOCUMENT_TEMPLATE -Encoding UTF8

            # Génération de la date courante dans les formats nécessaires
            $curDateYYYYMMDDHHMM = Get-Date -Format "yyyyMMddHHmm"
            $curDateGoodLooking = Get-Date -Format "dd.MM.yyyy HH:mm"
            
            $logHistory.addLineAndDisplay("Looking for entities...")

            # Chemin jusqu'à la grille tarifaire et on regarde qu'elle existe bien.
            $billingGridPDFFile = ([IO.Path]::Combine($global:XAAS_BILLING_DATA_FOLDER, $service, $serviceBillingInfos.billingGrid))
            if(!(Test-Path $billingGridPDFFile))
            {
                Throw ("Billing grid file not found for service ({0})" -f $billingGridPDFFile)
            }

            # Recherche des entités à facturer
            $entityList = $billingObject.getEntityList()

            $logHistory.addLineAndDisplay(("{0} entities found" -f $entityList.count))
            
            # Parcours des entités
            ForEach($entity in $entityList)
            {
                $logHistory.addLineAndDisplay(("Processing entity {0} ({1})..." -f $entity.entityElement, $entity.entityType))

                $counters.inc('entityProcessed')

                ## 1. On commence par créer le code HTML pour les items à facturer 

                $billingItemListHtml = ""
                $quantityTot = 0
                $totalPrice = 0
                
                # Les dates de début et de fin de facturation
                $billingBeginDate = $null
                $billingEndDate = $null

                $logHistory.addLineAndDisplay(("> Looking for items for service '{0}' ({1})" -f $service, $serviceBillingInfos.itemTypeInDB))

                # Recherche pour les éléments qu'il faut facturer et qui ne l'ont pas encore été
                $itemList = $billingObject.getEntityItemToBeBilledList($entity.entityId, $serviceBillingInfos.itemTypeInDB)

                $logHistory.addLineAndDisplay(("> {0} found = {1}" -f $serviceBillingInfos.itemTypeInDB, $itemList.count))

                # Parcours des éléments à facturer
                ForEach($item in $itemList)
                {
                    $monthYear = (getItemDateMonthYear -month $item.itemMonth -year $item.itemYear)

                    # Initialisation des dates pour comparaison
                    if($null -eq $billingBeginDate)
                    {
                        $billingBeginDate = $billingEndDate = [datetime]::parseexact($monthYear, 'MM.yyyy', $null)
                    }
                    else # On a les dates donc on peut comparer.
                    {
                        # On essaie de trouver la plus grande et la plus petite date
                        $tmpDate = [datetime]::parseexact($monthYear, 'MM.yyyy', $null)
                        if($tmpDate -lt $billingBeginDate)
                        {
                            $billingBeginDate = $tmpDate
                        }
                        elseif($tmpDate -gt $billingEndDate)
                        {
                            $billingEndDate = $tmpDate
                        }
                    }


                    $logHistory.addLineAndDisplay((">> Processing {0} '{1}'... " -f $serviceBillingInfos.itemTypeInDB, $item.itemName))

                    <# On ajoute l'unité à la description car passe celle-ci à Copernic en tant que "vraie" unité implique d'avoir déclaré 
                        celle-ci au préalable dans Copernic et si elle n'existe pas, l'erreur est mal gérée. Quentin Estoppey conseille de 
                        plutôt mettre l'unité dans la description de l'élément, ce qu'on fait donc ici #>
                    $descriptionWithUnit = "{0} [{1}]" -f $item.itemDesc, $item.itemUnit

                    $billingItemReplacements = @{
                        prestationCode = $serviceBillingInfos.prestationCode
                        description = $descriptionWithUnit
                        monthYear = $monthYear
                        quantity = $item.itemQuantity
                        unit = $item.itemUnit
                        unitPrice = $serviceBillingInfos.unitPricePerMonthCHF
                        # On coupe le prix à 2 décimales
                        itemPrice = truncateToNbDecimal -number ([double]($item.itemQuantity) * $serviceBillingInfos.unitPricePerMonthCHF) -nbDecimals 2
                    }

                    # Mise à jour des totaux pour la facture
                    $totalPrice += $billingItemReplacements.itemPrice
                    $quantityTot += $billingItemReplacements.quantity

                    # Création du HTML pour représenter l'item courant et ajout au code HTML représentant tous les items
                    $billingItemListHtml += (replaceInString -str $billingItemTemplate -valToReplace $billingItemReplacements)

                } # FIN Boucle de parcours des éléments à facturer 


                ## 2. On passe maintenant à création de la facture de l'entité en elle-même

                # S'il y a des éléments à facturer
                if($itemList.count -gt 0)
                {
                    
                    # Si on n'a pas atteint le montant minimum pour émettre une facture pour l'entité courante,
                    if($totalPrice -lt $global:BILLING_MIN_MOUNT_CHF)
                    {
                        $logHistory.addLineAndDisplay(("Entity '{0}' won't be billed this month, bill amount to small ({1} CHF)" -f $entity.entityElement, $totalPrice))
                        $counters.inc('billSkippedToLow')
                    }
                    else # On a atteint le montant minimum pour facturer 
                    {

                        # Référence de la facture
                        $billReference = ("{0}_{1}_{2}" -f $serviceBillingInfos.serviceName, $curDateYYYYMMDDHHMM, $entity.entityFinanceCenter) 

                        $periodStartDate = Get-Date -Format "MM.yyyy" -Date $billingBeginDate
                        $periodEndDate = Get-Date -Format "MM.yyyy" -Date $billingEndDate

                        # Elements à remplacer dans le document racine permettant de générer le HTML
                        $billingDocumentReplace = @{

                            docTitle = $serviceBillingInfos.docTitle

                            # Entête
                            billingForType = $entity.entityType
                            billingForElement = $entity.entityElement
                            billReference = $billReference
                            financeCenter = $entity.entityFinanceCenter
                            reportDate = $curDateGoodLooking 
                            periodStartDate = $periodStartDate
                            periodEndDate = $periodEndDate

                            billingReference = $serviceBillingInfos.billingReference
                            billingFrom = $serviceBillingInfos.billingFrom

                            # Nom des colonnes
                            colCode = $serviceBillingInfos.itemColumns.colCode
                            colDesc = $serviceBillingInfos.itemColumns.colDesc
                            colMonthYear = $serviceBillingInfos.itemColumns.colMonthYear
                            colConsumed = $serviceBillingInfos.itemColumns.colConsumed
                            colUnit = $serviceBillingInfos.itemColumns.colUnit
                            colUnitPrice = $serviceBillingInfos.itemColumns.colUnitPrice
                            colTotPrice = $serviceBillingInfos.itemColumns.colTotPrice

                            # Liste des élément facturés 
                            billingItems = $billingItemListHtml

                            # Dernière ligne du tableau
                            quantityTot = $quantityTot
                            unitPricePerMonthCHF = $serviceBillingInfos.unitPricePerMonthCHF
                            totalPrice = $totalPrice
                        }
                        
                        $billingTemplateHtml= replaceInString -str $billingTemplate -valToReplace $billingDocumentReplace 

                        # Génération du nom du fichier PDF de sortie
                        $PDFFilename = "{0}__{1}.pdf" -f ($billReference, $entity.entityElement)
                        $targetPDFPath = ([IO.Path]::Combine($global:XAAS_BILLING_PDF_FOLDER, $PDFFilename))

                        $logHistory.addLineAndDisplay(("> Generating PDF '{0}'" -f $targetPDFPath))
                        ConvertHTMLtoPDF -Source $billingTemplateHtml -Destination $targetPDFPath -binFolder $global:BINARY_FOLDER -author $serviceBillingInfos.pdfAuthor -landscape $true    
                        $counters.inc('PDFGenerated')

                        # S'il faut envoyer à Copernic,
                        if($sendToCopernic)
                        {
                            $billDescription = "{0} - du {1} au {2}" -f $serviceBillingInfos.itemTypeInDB, $periodStartDate, $periodEndDate

                            # Ajout de la facture dans Copernic avec le mode d'exécution spécifié
                            $result = $copernic.addBill($serviceBillingInfos, $billReference, $billDescription, $targetPDFPath, $billingGridPDFFile, $entity, $itemList, $execMode)
                            
                            # Si une erreur a eu lieu
                            if($null -ne $result.error)
                            {
                                # Enregistrement de l'erreur
                                $errorId = "{0}_{1}" -f (Get-Date -Format "yyyyMMdd_hhmmss"), $entity.entityId
                                $errorMsg = "Error adding Copernic Bill for entity '{0}'`nError message was: {1}" -f $entity.entityElement, $result.error
                                $errorFolder = saveRESTError -category "billing" -errorId $errorId -errorMsg $errorMsg -jsonContent $copernic.getLastBodyJSON()
                                $logHistory.addLineAndDisplay(("> Error sending bill to Copernic for entity ID (error: {0}). Details can be found in folder '{1}'" -f $result.error, $errorFolder))

                                $counters.inc('billCopernicError')

                                # Ajout du nécessaire pour les notifications
                                $notifications.copernicBillNotSent += "{0} ({1}) - Error logs are on {2} in folder {3} " -f $entity.entityElement, $entity.entityType, $env:computername, $errorFolder
                            }
                            else # Pas d'erreur
                            {
                                # Si on est en mode d'exéution réel et que la facture a bel et bien été envoyée dans Copernic 
                                if($copernicRealMode)
                                {
                                    $logHistory.addLineAndDisplay(("> Bill sent to Copernic (Doc number: {0}, bill ref: {1})" -f $result.docNumber, $billReference))

                                    # On dit que tous les items de la facture ont été facturés
                                    $billingObject.setEntityItemTypeAsBilled($entity.entityId, $serviceBillingInfos.itemTypeInDB, $billReference)
                                }
                                else # On est en mode "simulation" donc pas d'envoi réel de facture
                                {
                                    $logHistory.addLineAndDisplay("> Bill sent to Copernic in SIMULATION MODE without any error")
                                }

                                $logHistory.addLineAndDisplay(("> {0} items '{1}' set as billed for entity '{2}'" -f $itemList.count, $serviceBillingInfos.itemTypeInDB, $entity.entityElement))
                                $counters.inc('billSentToCopernic')    

                            } # Fin si pas d'erreur
                            
                        }# Fin s'il faut envoyer à Copernic
                        
                        $counters.inc('billDone')

                    }# FIN SI on a atteint le montant minimum pour facturer
                
                }
                else # Il n'y a aucun élément à facturer
                {
                    $logHistory.addLineAndDisplay(("Nothing left to bill for entity {0}" -f $entity.entityElement))
                    $counters.inc('billSkippedNothing')
                }

            }# FIN BOUCLE de parcours des entités

            $logHistory.addLineAndDisplay(("Cleaning PDF files older than {0} day(s)..." -f $global:BILLING_KEEP_PDF_NB_DAYS))
            # Suppression des fichiers PDF trop "vieux"
            ForEach($pdfFile in (Get-ChildItem -Path $global:XAAS_BILLING_PDF_FOLDER -Filter "*.pdf" | Where-Object {$_.CreationTime -lt (Get-Date).addDays(-$global:BILLING_KEEP_PDF_NB_DAYS)}))
            {
                Remove-Item $pdfFile.FullName -Force
                $logHistory.addLineAndDisplay(("> PDF file deleted: {0}" -f $pdfFile.FullName))
                $counters.inc('PDFOldCleaned')
            }
        }
    }

    

    


    

    

    # Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv

    # Résumé des actions entreprises
    $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Création des informations pour l'envoi du mail d'erreur
	$valToReplace = @{	
        scriptName = $MyInvocation.MyCommand.Name
        computerName = $env:computername
        parameters = (formatParameters -parameters $PsBoundParameters )
        error = $errorMessage
        errorTrace =  [System.Net.WebUtility]::HtmlEncode($errorTrace)
    }

    # Envoi d'un message d'erreur aux admins 
    $notificationMail.send("Error in script '{{scriptName}}'", "global-error", $valToReplace) 
}
