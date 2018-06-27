<#
   BUT : Contient les fonctions donnant accès à l'API vRA

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

	Des exemples d'utilsiation des API via Postman peuvent être trouvés ici :
	https://github.com/vmwaresamples/vra-api-samples-for-postman


	REMARQUES :
	- Il semblerait que le fait de faire un update d'élément sans que rien ne change
	mette un verrouillage sur l'élément... donc avant de faire un update, il faut
	regarder si ce qu'on va changer est bien différent ou pas.

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class vRAPI
{
	hidden [string]$token
	hidden [string]$server
	hidden [string]$tenant
	hidden [System.Collections.Hashtable]$headers

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $tenant			-> Nom du tenant auquel se connecter
		IN  : $userAtDomain	-> Nom d'utilisateur (user@domain)
		IN  : $password			-> Mot de passe

		RET : ID du token
	#>
	vRAPI([string] $server, [string] $tenant, [string] $userAtDomain, [string] $password)
	{
		$this.server = $server
		$this.tenant = $tenant

		$this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')

		$replace = @{username = $userAtDomain
						 password = $password
						 tenant = $tenant}

		$body = $this.loadJSON("user-credentials.json", $replace)

		$uri = "https://{0}/identity/api/tokens" -f $this.server

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.token = (Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)).id

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Bearer {0}" -f $this.token))

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Charge un fichier JSON et renvoie le code.
				Le fichier doit se trouver dans le dossier spécifié par $global:JSON_TEMPLATE_FOLDER

		IN  : $file				-> Fichier JSON à charger
		IN  : $valToReplace	-> (optionnel) Dictionnaaire avec en clef la chaine de caractères
										à remplacer dans le code JSON (qui sera mise entre {{ et }} dans
										le fichier JSON). En valeur se trouve chaîne de caractères à
										mettre à la place de la clef

		RET : Objet créé depuis le code JSON
	#>
	hidden [Object] loadJSON([string] $file, [System.Collections.IDictionary] $valToReplace)
	{
		# Chemin complet jusqu'au fichier à charger
		$filepath = (Join-Path $global:JSON_TEMPLATE_FOLDER $file)

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("JSON file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$json = (Get-Content -Path $filepath) -join "`n"

		# S'il y a des valeurs à remplacer
		if($valToReplace -ne $null)
		{
			# Parcours des remplacements à faire
			foreach($search in $valToReplace.Keys)
			{
				# Recherche et remplacement de l'élément
				$json = $json -replace "{{$($search)}}", $valToReplace.Item($search)
			}
		}
		try
		{
			return $json | ConvertFrom-Json
		}
		catch
		{
			Throw ("Error converting JSON from file ({0})" -f $filepath)
		}
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		$uri = "https://{0}/identity/api/tokens/{1}" -f $this.server, $this.token

		Invoke-RestMethod -Uri $uri -Method Delete -Headers $this.headers
	}



	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
													Business Groups
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des BG

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau de BG
	#>
	hidden [Array] getBGListQuery([string] $queryParams)
	{
		$uri = "https://{0}/identity/api/tenants/{1}/subtenants/?page=1&limit=9999" -f $this.server, $this.tenant

		# Si on doit ajouter des paramètres
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content
	}
	hidden [Array] getBGListQuery()
	{
		return $this.getBGListQuery($null)
	}



	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des BG

		RET : Tableau de BG
	#>
	[Array] getBGList()
	{
		return $this.getBGListQuery()
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des BG dont le nom contient la chaine de caractères passée
				en paramètre

		IN  : $str	-> la chaine de caractères qui doit être contenue dans le nom du BG

		RET : Tableau de BG
	#>
	[Array] getBGListMatch([string]$str)
	{
		return $this.getBGListQuery("`$filter=substringof('{0}', name)" -f $str)
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un BG donné par son nom

		IN  : $name	-> Le nom du BG que l'on désire

		RET : Objet contenant le BG
				$null si n'existe pas
	#>
	[PSCustomObject] getBG([string] $name)
	{
		$list = $this.getBGListQuery("`$filter=name eq '{0}'" -f $name)

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un BG

		IN  : $name					-> Nom du BG à ajouter
		IN  : $desc					-> Description du BG
		IN  : $capacityAlertsEmail	-> Adresse mail où envoyer les mails de capacity alert
									  (champ "send capacity alert emails to:")
		IN  : $machinePrefixId  	-> ID du prefix de machine à utiliser
									   Si on veut prendre le préfixe par défaut de vRA, on
									   peut passer "" pour ce paramètre.
		IN  : $customProperties		-> Dictionnaire avec les propriétés custom à ajouter


		RET : Objet contenant le BG
	#>
	[PSCustomObject] addBG([string]$name, [string]$desc, [string]$capacityAlertsEmail, [string]$machinePrefixId, [System.Collections.Hashtable] $customProperties)
	{
		$uri = "https://{0}/identity/api/tenants/{1}/subtenants" -f $this.server, $this.tenant

		# Valeur à mettre pour la configuration du BG
		$replace = @{name = $name
						 description = $desc
						 tenant = $this.tenant
						 capacityAlertsEmail = $capacityAlertsEmail}

		# Si on a passé un ID de préfixe de machine,
		if($machinePrefixId -ne "")						 
		{
			$replace.machinePrefixId = $machinePrefixId
		}
		else 
		{
			$replace.machinePrefixId = $null
		}

		
		$body = $this.loadJSON("business-group.json", $replace)

		# Ajout des éventuelles custom properties
		$customProperties.Keys | ForEach {

			$body.extensionData.entries += $this.loadJSON("business-group-extension-data-custom.json", `
															 			 @{"key" = $_
															 			  "value" = $customProperties.Item($_)})
		}

		# Création du BG
		Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)

		# Recherche et retour du BG
		return $this.getBG($name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un BG.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $bg					-> Objet du BG à mettre à jour
		IN  : $newName				-> (optionnel -> "") Nouveau nom
		IN  : $newDesc				-> (optionnel -> "") Nouvelle description
		IN  : $machinePrefixId  	-> (optionnel -> "") ID du prefix de machine à utiliser
		IN  : $customProperties		-> (optionnel -> $null) La liste des "custom properties" (et leur valeur) à mettre à
									   jour

		RET : Objet contenant le BG mis à jour
	#>
	[PSCustomObject] updateBG([PSCustomObject] $bg, [string] $newName, [string] $newDesc, [string]$machinePrefixId, [System.Collections.IDictionary]$customProperties)
	{
		$uri = "https://{0}/identity/api/tenants/{1}/subtenants/{2}" -f $this.server, $this.tenant, $bg.id

		# S'il faut mettre le nom à jour,
		if($newName -ne "")
		{
			$bg.name = $newName
		}

		# S'il faut mettre la description à jour,
		if($newDesc -ne "")
		{
			$bg.description = $newDesc
		}

		if($machinePrefixId -ne "")
		{
			$customProperties['iaas-machine-prefix'] = $machinePrefixId
		}

		# S'il faut mettre à jour une ou plusieurs "custom properties"
		if($customProperties -ne $null)
		{

			# Parcour des custom properties à mettre à jour,
			$customProperties.Keys | ForEach-Object {

				$customPropertyKey = $_

				# Recherche de l'entrée pour la "Custom property" courante à modifier
				$entry = $bg.extensionData.entries | Where-Object { $_.key -eq $customPropertyKey}

				# Si une entrée a été trouvée
				if($entry -ne $null)
				{
					# Mise à jour de sa valeur en fonction du type de la custom propertie
					switch($entry.value.type)
					{
						'complex'
						{
							($entry.value.values.entries | Where-Object {$_.key -eq "value"}).value.value = $customProperties.Item($customPropertyKey)
							break
						}

						'string'
						{
							$entry.value.value = $customProperties.Item($customPropertyKey)
							break
						}

						default:
						{
							Write-Error ("Custom property type '{0}' not supported!" -f $entry.value.type)
						}
					}

				}
				else # Aucune entrée n'a été trouvée
				{
					# Ajout des infos avec le template présent dans le fichier JSON
					$bg.ExtensionData.entries += $this.loadJSON("business-group-extension-data.json", `
																			@{"key" = $customPropertyKey
																			"value" = $customProperties.Item($customPropertyKey)})
				}

			} # FIN BOUCLE de parcours des "custom properties" à mettre à jour
		}

		# Mise à jour des informations
		Invoke-RestMethod -Uri $uri -Method Put -Headers $this.headers -Body (ConvertTo-Json -InputObject $bg -Depth 20)

		return $bg
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un business group

		IN  : $BGID		-> ID du Business Group à supprimer
	#>
	[void] deleteBG($bgId)
	{
		$uri = "https://{0}/identity/api/tenants/{1}/subtenants/{2}" -f $this.server, $this.tenant, $bgId

		# Mise à jour des informations
		Invoke-RestMethod -Uri $uri -Method Delete -Headers $this.headers
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
											Business Groups Roles
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Retourne le contenu d'un rôle pour un BG

		IN  : $BGID		-> ID du BG auquel supprimer le rôle
		IN  : $role		-> Nom du rôle auquel ajouter le groupe/utilisateur AD
								Group manager role 	=> CSP_SUBTENANT_MANAGER
								Support role 			=> CSP_SUPPORT
								Shared access role	=> CSP_CONSUMER_WITH_SHARED_ACCESS
								User role				=> CSP_CONSUMER
	#>
	[Array] getBGRoleContent([string] $BGID, [string] $role)
	{
		$uri = "https://{0}/identity/api/tenants/{1}/subtenants/{2}/roles/{3}/principals/" -f $this.server, $this.tenant, $BGID, $role

		# Suppression du rôle
		$res =  (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers ).content

		return $res

	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime le contenu d'un rôle pour un BG

		IN  : $BGID		-> ID du BG auquel supprimer le rôle
		IN  : $role		-> Nom du rôle auquel ajouter le groupe/utilisateur AD
								Group manager role 	=> CSP_SUBTENANT_MANAGER
								Support role 			=> CSP_SUPPORT
								Shared access role	=> CSP_CONSUMER_WITH_SHARED_ACCESS
								User role				=> CSP_CONSUMER
	#>
	[Void] deleteBGRoleContent([string] $BGID, [string] $role)
	{
		# S'il y a du contenu pour le rôle
		if(($this.getBGRoleContent($BGID, $role)).count -gt 0)
		{
			$uri = "https://{0}/identity/api/tenants/{1}/subtenants/{2}/roles/{3}/" -f $this.server, $this.tenant, $BGID, $role

			# Suppression du contenu du rôle
			$empty = Invoke-RestMethod -Uri $uri -Method Delete -Headers $this.headers
		}

	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Ajouter un élément (groupe/utilisateur AD) à un rôle donné d'un BG

		IN  : $BGID							-> ID du BG auquel ajouter le rôle
		IN  : $role							-> Nom du rôle auquel ajouter le groupe/utilisateur AD
													Group manager role 	=> CSP_SUBTENANT_MANAGER
													Support role 			=> CSP_SUPPORT
													Shared access role	=> CSP_CONSUMER_WITH_SHARED_ACCESS
													User role				=> CSP_CONSUMER
		IN  : $userOrGroupAtDomain		-> Utilisateur/groupe AD à ajouter
													<user>@<domain>
													<group>@<domain>

		RET : Rien
	#>
	[Void] addRoleToBG([string] $BGID, [string] $role, [string] $userOrGroupAtDomain)
	{
		# Séparation des informations
		$userOrGroup, $domain = $userOrGroupAtDomain.split('@')

		$uri = "https://{0}/identity/api/tenants/{1}/subtenants/{2}/roles/{3}/principals" -f $this.server, $this.tenant, $BGID, $role


		# ******
		# Pour cette fois-ci on ne charge pas depuis le JSON car c'est un tableau contenant un dictionnaire.
		# Et dans cette version de PowerShell, si le JSON commence par un tableau, le reste est mal interprêté.
		# Dans le cas courant, ce qui est dans le tableau (un dictionnaire), ce n'est pas un objet IDictionnary
		# qui sera créé mais un PSCustomObject basique...
		# Le problème est corrigé dans la version 6.0 De PowerShell mais celle-ci s'installe par défaut en parallèle
		# de la version 5.x de PowerShell et donc les éditeurs de code ne la prennent pas en compte... donc pas
		# possible de faire du debugging.
		# Valeurs à remplacer
		<#
		$replace = @{name = $userOrGroup
						 domain = $domain}

		$body = vRALoadJSON -file "business-group-role-principal.json"  -valToReplace $replace
		#>
		# ******

		$body = @(
			@{
				name = $userOrGroup
				domain = $domain
			}
		)

		# Ajout du rôle
		$empty = Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 2 )
	}




	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
													Entitlements
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des entitlements basée sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des entitlements
	#>
	hidden [Array] getEntListQuery([string] $queryParams)
	{
		$uri = "https://{0}/catalog-service/api/entitlements/?page=1&limit=9999" -f $this.server

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content

	}
	hidden [Array] getEntListQuery()
	{
		return $this.getEntListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie l'entitlement d'un BG

		IN  : $BGID 	-> ID du BG pour lequel on veut l'entitlement

		RET : L'entitlement ou $null si pas trouvé
	#>
	[PSCustomObject] getBGEnt([string]$BGID)
	{
		$ent = $this.getEntListQuery() | Where-Object {$_.organization.subtenantRef -eq $BGID}

		if($ent.Count -eq 0){return $null}
		return $ent[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des entitlements

		RET : Liste des entitlements
	#>
	[Array] getEntList()
	{
		return $this.getEntListQuery()
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Entitlements dont le nom contient la chaine de caractères
				passée en paramètre

		IN  : $str	-> la chaine de caractères qui doit être contenue dans le nom de l'entitlement

		RET : Tableau de Entitlements
	#>
	[Array] getEntListMatch([string]$str)
	{
		return $this.getEntListQuery("`$filter=substringof('{0}', name)" -f $str)
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Entitlements pour le BG dont l'ID est passé en paramètre

		IN  : $BGID	-> ID du BG dont on veut les entitlements

		RET : Tableau de Entitlements
	#>
	[Array] getBGEntList([string]$BGID)
	{
		return $this.getEntListQuery() | Where-Object {$_.organization.subtenantRef -eq $BGID}
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un entitlement donné par son nom

		IN  : $name -> le nom

		RET : Liste des entitlements
	#>
	[PSCustomObject] getEnt([string]$name)
	{
		$list = $this.getEntListQuery("`$filter=name eq '{0}'" -f $name)

		if($list.Count -eq 0){return $null}
		return $list[0]

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un entitlement

		IN  : $name		-> Nom
		IN  : $desc		-> Description
		IN  : $BGID		-> ID du Business Group auquel lier l'entitlement
		IN  : $bgName	-> Nom du Business Group auquel lier l'entitlement

		RET : L'entitlement ajouté
	#>
	[PSCustomObject] addEnt([string]$name, [string]$desc, [string]$BGID, [string]$bgName)
	{
		$uri = "https://{0}/catalog-service/api/entitlements" -f $this.server

		# Valeur à mettre pour la configuration du BG
		$replace = @{name = $name
						 description = $desc
						 tenant = $this.tenant
						 bgID = $BGID
						 bgName = $bgName}

		$body = $this.loadJSON("entitlement.json", $replace)

		$empty = Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 10 )

		return $this.getEnt($name)

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un Entitlement.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $ent			-> Objet de l'entitlement à mettre à jour
		IN  : $newName		-> (optionnel -> "") Nouveau nom
		IN  : $newDesc		-> (optionnel -> "") Nouvelle description
		IN  : $activated	-> Pour dire si l'Entitlement doit être activé ou pas.

		RET : Objet contenant l'entitlement mis à jour
	#>
	[PSCustomObject] updateEnt([PSCustomObject] $ent, [string] $newName, [string] $newDesc, [bool]$activated)
	{
		$uri = "https://{0}/catalog-service/api/entitlements/{1}" -f $this.server, $ent.id

		# S'il faut mettre le nom à jour,
		if($newName -ne "")
		{
			$ent.name = $newName
		}

		# S'il faut mettre la description à jour,
		if($newDesc -ne "")
		{
			$ent.description = $newDesc
		}

		# En fonction de s'il faut activer ou pas
		if($activated)
		{
			$ent.status = "ACTIVE"
			$ent.statusName = "Active"
		}
		else
		{
			$ent.status = "INACTIVE"
			$ent.statusName = "Inactive"
		}

		# Mise à jour des informations
		$empty = Invoke-RestMethod -Uri $uri -Method Put -Headers $this.headers -Body (ConvertTo-Json -InputObject $ent -Depth 20)

		return $ent
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un Entitlement.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $ent			-> Objet de l'entitlement à mettre à jour (et contenant les infos
								mises à jour)
		IN  : $activated	-> Pour dire si l'Entitlement doit être activé ou pas.

		RET : Objet contenant l'entitlement mis à jour
	#>
	[PSCustomObject] updateEnt([PSCustomObject] $ent, [bool]$activated)
	{
		# Réutilisation de la méthode en passant des paramètres vides.
		return $this.updateEnt($ent, $null, $null, $activated)
	}



	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un entitlement

		IN  : $entId	-> ID de l'Entitlement à supprimer
	#>
	[void] deleteEnt([string]$entID)
	{
		$uri = "https://{0}/catalog-service/api/entitlements/{1}" -f $this.server, $entId

		$empty = Invoke-RestMethod -Uri $uri -Method Delete -Headers $this.headers
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
													Service
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Services basé sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des Services
	#>
	hidden [Array] getServiceListQuery([string] $queryParams)
	{
		$uri = "https://{0}/catalog-service/api/services/?page=1&limit=9999" -f $this.server

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content
	}
	hidden [Array] getServiceListQuery()
	{
		return $this.getServiceListQuery($null)
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Services contenant une chaine de caractères donnée

		IN  : $str		-> (optionnel) Chaine de caractères que doit contenir le nom

		RET : Liste des Services
	#>
	[Array] getServiceListMatch([string] $str)
	{
		return $this.getServiceListQuery("`$filter=substringof('{0}', name)" -f $str)

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Préparer un objet contenant un Entitlement en lui ajoutant le service passé
				en paramètre.
				Afin de réellement ajouter les services pour l'Entitlement dans vRA, il faudra
				appeler la méthode updateEnt() en passant l'objet en paramètre.

		IN  : $ent				-> Objet de l'entitlement auquel ajouter le service
		IN  : $serviceID		-> ID du service à ajouter
		IN  : $serviceName		-> Nom du service à ajouter
		IN  : $approvalPolicy	-> Objet de l'approval policy.

		RET : Objet contenant Entitlement avec le nouveau service
	#>
	[PSCustomObject] prepareAddEntService([PSCustomObject] $ent, [string]$serviceID, [string]$serviceName, [PSCustomObject]$approvalPolicy)
	{
		# Valeur à mettre pour la configuration du Service
		$replace = @{id = $serviceID
					label = $serviceName
					approvalPolicyId = $approvalPolicy.id}

		# Création du nécessaire pour le service à ajouter
		$service = $this.loadJSON("entitlement-service.json", $replace)

		# Ajout du service à l'objet
		$ent.entitledServices += $service

		# Retour de l'entitlement avec le nouveau Service.
		return $ent
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Prépare un Objet contenant un Entitlement en initialisant la liste des actions
				2nd day.
				Afin de réellement ajouter les actions pour l'Entitlement dans vRA, il faudra
				appeler la méthode updateEnt() en passant l'objet en paramètre.

		IN  : $ent				-> Objet de l'entitlement auquel ajouter les actions
		IN  : $actionList		-> Tableau contenant la liste des actions à ajouter.
										Ce tableau contient des hashtable (dictionnaires) avec
										.appliesTo: le descriptif de l'élément auquel appliquer l'action
												   	ex: "Infrastructure.Virtual" pour les VM
										.action: le texte de l'action à ajouter, tel que défini
													dans vRA.
													ex: "Destroy", "Create Snapshot"
										.needsApproval: $true|$false pour dire si l'action doit passer
													par une policy d'approbation ou pas.
		IN  : $approvalPolicy	-> Object Approval Policy à utiliser dans le cas où une action doit 
									être approuvée

		RET : Objet contenant l'Entitlement avec les actions passée.
	#>
	[PSCustomObject] prepareEntActions([PSCustomObject] $ent, [Array]$actionList, [PSCustomObject]$approvalPolicy)
	{
		# Pour stocker la liste des actions à ajouter, avec toutes les infos nécessaires
		$actionsToAdd = @()

		# Parcours des actions à ajouter
		ForEach($actionInfos in $actionList)
		{
			# Si on a trouvé des infos pour l'action demandée,
			if(($vRAAction = $this.getAction($actionInfos.action, $actionInfos.appliesTo))-ne $null)
			{
				# Définition de l'ID d'approval policy à utiliser dans le cas où on doit approuver l'action
				if($actionInfos.needsApproval)
				{
					$approvalPolicyId = $approvalPolicy.id
				}
				else 
				{
					$approvalPolicyId = $null	
				}

				# Valeur à mettre pour la configuration du BG
				$replace = @{resourceOperationRef_id = $vRAAction.id
								 resourceOperationRef_label = $vRAAction.name
								 externalId = $vRAAction.externalId
								 targetResourceTypeRef_id = $vRAAction.targetResourceTypeRef.id
								 targetResourceTypeRef_label = $vRAAction.targetResourceTypeRef.label
								 approvalPolicyId = $approvalPolicyId}

				# Création du nécessaire pour l'action à ajouter
				$actionsToAdd += $this.loadJSON("entitlement-action.json", $replace)
			}
			else # Pas d'infos trouvées pour l'action
			{
				Write-Error ("prepareEntActions(): No information found for action '{0}' for element '{1}'" -f $actionInfos.action, $actionInfos.appliesTo)
			}
		}

		# Ajout du service à l'objet
		$ent.entitledResourceOperations = $actionsToAdd

		# Retour de l'entitlement avec les actions
		return $ent
	}




	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Reservations
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Reservations basé sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des Reservations
	#>
	hidden [Array] getResListQuery([string] $queryParams)
	{
		$uri = "https://{0}/reservation-service/api/reservations/?page=1&limit=9999" -f $this.server

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content

	}
	hidden [Array] getResListQuery()
	{
		return $this.getResListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Reservations contenant une chaine de caractères donnée

		IN  : $nameContains		-> (optionel) Chaine de caractères que doit contenir le nom

		RET : Liste des Reservations
	#>
	[Array] getResListMatch([string] $str)
	{
		return $this.getResListQuery("`$filter=substringof('{0}', name)" -f $str)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une Reservation donnée par son nom

		IN  : $name	-> Le nom de la Reservation que l'on désire

		RET : Objet contenant la Reservation
				$null si n'existe pas
	#>
	[PSCustomObject] getRes([string] $name)
	{
		$list = $this.getResListQuery("`$filter=name eq '{0}'" -f $name)

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Reservations d'un BG

		IN  : $bgID	-> ID du BG dont on veut les Reservations

		RET : Liste des Reservation
	#>
	[PSCustomObject] getBGResList([string] $bgID)
	{
		return $this.getResListQuery("`$filter=subTenantId eq '{0}'" -f $bgID)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une Reservation à partir d'un template

		IN  : $resTemplate	-> Objet contenant le Template à utiliser pour ajouter la Reservation
		IN  : $name				-> Nom
		IN  : $tenant			-> Nom du Tenant
		IN  : $BGID				-> ID du Business Group auquel lier la Reservation

		RET : L'entitlement ajouté
	#>
	[PSCustomObject] addResFromTemplate([PSCustomObject]$resTemplate, [string]$name, [string]$tenant, [string]$BGID)
	{
		$uri = "https://{0}/reservation-service/api/reservations" -f $this.server

		# Mise à jour des champs pour pouvoir ajouter la nouvelle Reservation
		$resTemplate.name = $name
		$resTemplate.tenantId = $tenant
		$resTemplate.subTenantId = $BGID
		# Suppression de la référence au template
		$resTemplate.id = $null
		# On repart de 0 pour la version
		$resTemplate.version = 0
		# On l'active (dans le cas où le Template était désactivé)
		$resTemplate.enabled = $true

		$empty = Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $resTemplate -Depth 20 )

		return $this.getRes($name)

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met le nom d'une Reservation à jour

		IN  : $res		-> Objet contenant la Reservation à mettre à jour.
		IN  : $newName	-> Le nouveau nom de la Reservation

		RET : Objet contenant la Reservation mise à jour
	#>
	[PSCustomObject] updateRes([PSCustomObject]$res, [string]$newName)
	{
		$uri = "https://{0}/reservation-service/api/reservations/{1}" -f $this.server, $res.id

		$res.name = $newName

		$empty = Invoke-RestMethod -Uri $uri -Method Put -Headers $this.headers -Body (ConvertTo-Json -InputObject $res -Depth 20 )

		return $res
	}



	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime une Reservation

		IN  : $resId	-> Id de la Reservation à supprimer
	#>
	[void] deleteRes([string]$resID)
	{
		$uri = "https://{0}/reservation-service/api/reservations/{1}" -f $this.server, $resID

		$empty = Invoke-RestMethod -Uri $uri -Method Delete -Headers $this.headers

	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Resources Actions
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des actions (2nd day) basé sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des actions
	#>
	hidden [Array] getActionListQuery([string] $queryParams)
	{
		$uri = "https://{0}/catalog-service/api/resourceOperations/?page=1&limit=9999" -f $this.server

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content

	}
	hidden [Array] getActionListQuery()
	{
		return $this.getActionListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une action (2nd day) donnée par son nom et l'élément auquel elle s'applique

		IN  : $name			-> Le nom de l'action que l'on désire (c'est celui affiché dans la GUI)
		IN  : $appliesTo	-> Chaîne de caractères avec l'ID du type de ressource auquel s'applique
									cette action.
									Ex: "Infrastructure.Virtual" pour une VM
								Dans le cas où l'action aurait été développée en interne, ce paramètre
								doit être mis à "" 

		RET : Objet contenant l'action
				$null si n'existe pas
	#>
	[PSCustomObject] getAction([string] $name, [string]$appliesTo)
	{
		# Si c'est une action développée en interne
		if($appliesTo -eq "")
		{
			# Pas de filtre
			$appliesToFilter = ""
		}
		else # Action prédéfinie
		{
			# Filtre
			$appliesToFilter = "startswith(externalId, '{0}') and" -f $appliesTo
		}
		
		$list = $this.getActionListQuery(("`$filter=({0} name eq '{1}')" -f $appliesToFilter, $name))

		if($list.Count -eq 0){return $null}
		return $list[0]
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Principals
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des principals basé sur les potentiels critères passés en
				paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des Custom groups
	#>
	hidden [Array] getPrincipalsListQuery([string] $queryParams)
	{
		$uri = "https://{0}/identity/api/authorization/tenants/{1}/principals/?page=1&limit=9999" -f $this.server, $this.tenant

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content

	}
	hidden [Array] getPrincipalsListQuery()
	{
		return $this.getPrincipalsListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Custom groups
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des admins pour le tenant courant.

		RET : Liste des admins
	#>
	[Array] getTenantAdminGroupList()
	{
		return $this.getPrincipalsListQuery() | Where-Object {($_.tenant -eq $this.tenant) -and ($_.principalRef.domain -eq $this.tenant)}
	}



	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Machine prefixes
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des préfixes de machines basé sur les potentiels critères de
				recherche passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des préfixes de machines
	#>
	hidden [Array] getMachinePrefixListQuery([string] $queryParams)
	{
		$uri = "https://{0}/iaas-proxy-provider/api/machine-prefixes/?page=1&limit=9999" -f $this.server, $this.tenant

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content

	}
	hidden [Array] getMachinePrefixListQuery()
	{
		return $this.getMachinePrefixListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un préfix de machine donné par son nom

		IN  : $name	-> Le nom du préfix de machine que l'on désire

		RET : Objet contenant le préfix
				$null si n'existe pas
	#>
	[PSCustomObject] getMachinePrefix([string] $name)
	{
		$list = $this.getMachinePrefixListQuery("`$filter=name eq '{0}'" -f $name)

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Business Group Items
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items d'un BG.
			  On utilise la puissance de PowerShell pour filtrer sur les objets renvoyés car
			  impossible de faire fonctionner le filtre... le paramètre est pris en compte (pas d'erreur)
			  mais n'est pas appliqué... c'est pour cette raison qu'on fait un "Where-Object" sur le résultat
			  avant de le renvoyer.


		IN  : $bg				-> Objet représentant le BG pour lequel on veut la liste des Items

		RET : Tableau contenant les items
	#>
	[Array] getBGItemList([PSObject] $bg)
	{
		$uri = "https://{0}/catalog-service/api/consumer/resources/?page=1&limit=9999" -f $this.server


		return ((Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content | Where-Object {
			($_.organization.subtenantRef -eq $bg.id)})

	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Directories
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Lance la synchro d'un directory (ex: Active Directory)

		IN  : $name	-> Nom du directory que l'on veut synchroniser
	#>
	[void] syncDirectory([string] $name)
	{
		$uri = "https://{0}/identity/api/tenants/{1}/directories/{2}/sync" -f $this.server, $this.tenant, $name

		Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Approval Policies
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Approve Policies

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau d'Approve Policies
	#>
	hidden [Array] getApprovePolicyListQuery([string] $queryParams)
	{
		$uri = "https://{0}/approval-service/api/policies?page=1&limit=9999" -f $this.server

		# Si on doit ajouter des paramètres
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content
	}
	hidden [Array] getApprovePolicyListQuery()
	{
		return $this.getBGListQuery($null)
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une Approve Policy basée sur son nom.

		IN  : $name	-> Le nom de l'approve policy que l'on désire

		RET : Objet contenant l'approve policy
				$null si n'existe pas
	#>
	[PSCustomObject] getApprovalPolicy([string] $name)
	{
		$list = $this.getApprovePolicyListQuery("`$filter=name eq '{0}'" -f $name)

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Créé une pré-approval policy qui spécifie un nom de groupe comme personnes pouvant
			  approuver.

		IN  : $name						-> Nom de la policy
		IN  : $desc						-> Description de la policy
		IN  : $approverGroupAtDomain	-> FQDN du groupe (<group>@<domain>) qui devra approuver.
		IN  : $approvalPolicyType   	-> Type de la policy :
                                        	$global:APPROVE_POLICY_TYPE__ITEM_REQ
                                        	$global:APPROVE_POLICY_TYPE__ACTION_REQ

		RET : L'approval policy créé
	#>
	[psobject] addUsrGrpPreApprovalPolicy([string]$name, [string]$desc, [string]$approverGroupAtDomain, [string]$approvalPolicyType)
	{
		$uri = "https://{0}/approval-service/api/policies" -f $this.server

		$approverDisplayName, $domain = $approverGroupAtDomain.split('@')

		# Valeur à mettre pour la configuration du BG
		$replace = @{preApprovalName = $name
			preApprovalDesc = $desc
			approverGroupAtDomain = $approverGroupAtDomain
			approverDisplayName = $approverDisplayName
			levelName = "Pre approve level"} 

		# Définition du nom de fichier à utiliser pour créer la policy en fonction du type de celle-ci.
		if($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ITEM_REQ)
		{
			$json_filename = "pre-approval-policy-usrgrp-new-item.json"
		}
		elseif($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ACTION_REQ)
		{
			$json_filename = "pre-approval-policy-usrgrp-reconfigure.json"
		}
		else 
		{
			Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
		}

		$body = $this.loadJSON($json_filename, $replace)

		# Création de la Policy
		Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)

		# Recherche et retour de l'Approval Policy ajoutée
		return $this.getApprovalPolicy($name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Créé une pré-approval policy qui passe par un "Subscription Event" pour la validation.

		IN  : $name						-> Nom de la policy
		IN  : $desc						-> Description de la policy
		IN  : $approverGroupAtDomain	-> FQDN du groupe (<group>@<domain>) qui devra approuver.
		IN  : $approvalPolicyType   	-> Type de la policy :
                                        	$global:APPROVE_POLICY_TYPE__ITEM_REQ
                                        	$global:APPROVE_POLICY_TYPE__ACTION_REQ

		RET : L'approval policy créé
	#>
	[psobject] addEvSubPreApprovalPolicy([string]$name, [string]$desc, [string]$approverGroupAtDomain, [string]$approvalPolicyType)
	{
		$uri = "https://{0}/approval-service/api/policies" -f $this.server

		# Valeur à mettre pour la configuration du BG
		$replace = @{preApprovalName = $name
			preApprovalDesc = $desc
			approverGroupAtDomain = $approverGroupAtDomain
			approverGroupCustomPropName = $global:VRA_CUSTOM_PROP_VRA_POL_APP_GROUP} 

		# Définition du nom de fichier à utiliser pour créer la policy en fonction du type de celle-ci.
		if($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ITEM_REQ)
		{
			$json_filename = "pre-approval-policy-evsub-new-item.json"
		}
		elseif($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ACTION_REQ)
		{
			$json_filename = "pre-approval-policy-evsub-reconfigure.json"
		}
		else 
		{
			Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
		}

		$body = $this.loadJSON($json_filename, $replace)

		# Création de la Policy
		Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)

		# Recherche et retour de l'Approval Policy ajoutée
		return $this.getApprovalPolicy($name)
	}	

	<#
		-------------------------------------------------------------------------------------
		BUT : Change l'état d'une approval policy donnée

		IN  : $approvalPolicy		-> Approval Policy dont on veut changer l'état
		IN  : $activated			-> $true|$false pour dire si la policy est activée ou pas

		RET : L'approval policy modifiée
	#>
	[psobject] setActivePolicyState([PSCustomObject]$approvalPolicy, [bool]$activated)
	{
		$uri = "https://{0}/approval-service/api/policies/{1}" -f $this.server, $approvalPolicy.id

		if($activated)
		{
			$approvalPolicy.state = "PUBLISHED"
			$approvalPolicy.stateName = "Active"
		}
		else 
		{
			$approvalPolicy.state = "RETIRED"
			$approvalPolicy.stateName = "Inactive"
		}

		# Mise à jour des informations
		Invoke-RestMethod -Uri $uri -Method Put -Headers $this.headers -Body (ConvertTo-Json -InputObject $approvalPolicy -Depth 20)

		return $approvalPolicy
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Efface une approval policy

		IN  : $approvalPolicy		-> Approval Policy qu'il faut effacer
		
		RET : rien
	#>
	[void] deleteApprovalPolicy([PSCustomObject]$approvalPolicy)
	{
		# On commence par la désactiver sinon on ne pourra pas la supprimer
		$approvalPolicy = $this.setActivePolicyState($approvalPolicy, $false)

		$uri = "https://{0}/approval-service/api/policies/{1}" -f $this.server, $approvalPolicy.id

		# Mise à jour des informations
		Invoke-RestMethod -Uri $uri -Method Delete -Headers $this.headers
		
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Approval Policies
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Subscriptions de l'event broker.

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau d'Approve Policies
	#>
	hidden [Array] getSubscriptionListQuery([string] $queryParams)
	{
		$uri = "https://{0}/advanced-designer-service/api/tenants/{1}/event-broker/subscriptions?page=1&limit=9999" -f $this.server, $this.tenant

		# Si on doit ajouter des paramètres
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).content
	}
	hidden [Array] getSubscriptionListQuery()
	{
		return $this.getSubscriptionListQuery($null)
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une Subscription de l'event broker basée sur son nom.

		IN  : $name	-> Le nom de l'approve policy que l'on désire

		RET : Objet contenant l'approve policy
				$null si n'existe pas
	#>
	[PSCustomObject] getSubscription([string] $name)
	{
		$list = $this.getSubscriptionListQuery("`$filter=name eq '{0}'" -f $name)

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


		<#
		-------------------------------------------------------------------------------------
		BUT : Créé une Subscription dans l'event broker. Celle-ci sera exécutée sous des 
			  conditions données et se chargera de lancer un Workflow vRO

		IN  : $name						-> Nom de la policy
		IN  : $desc						-> Description de la policy
		IN  : $vROWorkflowID			-> ID du Workflow vRO à lancer 
		IN  : $approvalLevelName   		-> Nom de l'approval level appartenant à l'approval policy
										   auquel il faut relier la Subscription.
		IN  : $approvalPolicyType   	-> Type de la policy à laquelle on lie la Subscription :
                                        	$global:APPROVE_POLICY_TYPE__ITEM_REQ
                                        	$global:APPROVE_POLICY_TYPE__ACTION_REQ	

		RET : L'approval policy créé
	#>
	[psobject] addSubscription([string]$name, [string]$desc, [string]$vROWorkflowID, [string]$approvalLevelName, [string]$approvalPolicyType)
	{
		$uri = "https://{0}/advanced-designer-service/api/tenants/{1}/event-broker/subscriptions" -f $this.server, $this.tenant

		# Valeur à mettre pour la configuration du BG
		$replace = @{subscriptionName = $name
			subscriptionDesc = $desc
			vROWorkflowID = $vROWorkflowID
			approvalLevelName = $approvalLevelName
			tenant = $this.tenant} 

		# Définition du nom de fichier à utiliser pour créer la Subscription en fonction du type de l'approval policy liée.
		if($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ITEM_REQ)
		{
			$json_filename = "subscription-new-item.json"
		}
		elseif($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ACTION_REQ)
		{
			Throw "Not handled"
			#$json_filename = "pre-approval-policy-evsub-reconfigure.json"
		}
		else 
		{
			Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
		}

		$body = $this.loadJSON($json_filename, $replace)

		# Création de la Policy
		Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)

		# Recherche et retour de la Sbuscription ajoutée
		return $this.getSubscription($name)
	}	


}









