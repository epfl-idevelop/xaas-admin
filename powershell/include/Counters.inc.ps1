<#
   BUT : Contient une classe permetant de gérer des compteurs avec des descriptions

   AUTEUR : Lucien Chaboudez
   DATE   : Mars 2018

   ----------
   HISTORIQUE DES VERSIONS
   20.03.2018 - 1.0 - Version de base
#>
class Counters
{
    hidden [System.Collections.IDictionary]$counters = @{}

    Counters()
    {

    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Ajouter un compteur à la liste

        IN  : $id           -> Identifiant unique pour le compteur
        IN  : $description  -> Une description pour le compteur (sera utilisée pour l'affichage)

	#>
    [void] add([string] $id, [string]$description)
    {
        $this.counters.Add($id, @{description = $description
                               value = 0})
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Incrémente un compteur

        IN  : $id           -> Identifiant unique pour le compteur
    #>
    [void] inc([string]$id)
    {
        if($this.counters.Keys -contains $id)
        {
            $this.counters[$id]['value'] += 1
        }
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Initialise un compteur avec une valeur donnée

        IN  : $id           -> Identifiant unique pour le compteur
        IN  : $val          -> Valeur à mettre au compteur
    #>
    [void] set([string]$id, [int]$val)
    {
        if($this.counters.Keys -contains $id)
        {
            $this.counters[$id]['value'] = $val
        }
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie un compteur en fonction de son nom

        IN  : $id           -> Identifiant unique pour le compteur
    #>
    [int] get([string]$id)
    {
        if($this.counters.Keys -contains $id)
        {
            return $this.counters.Item($id)['value']
        }
        return 0
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la chaine de caractères représentant les compteurs

        IN  : $title    -> Le titre à afficher en entête des compteurs
    #>
    [string] getDisplay([string] $title)
    {
        $maxLength = 0

        # Parcours des compteurs pour trouver la description la plus longue
        foreach($id in $this.counters.Keys)
        {
            if($this.counters.Item($id)['description'].length -gt $maxLength)
            {
                $maxLength = $this.counters.Item($id)['description'].length
            }
        }
        $dash = "-"

        $code = "`n{0}`n{1}`n" -f $title, ($dash.PadRight($maxLength+5,$dash))

        foreach($id in $this.counters.Keys)
        {
            $code += ("{0}: {1}`n" -f $this.counters.Item($id)['description'].PadRight($maxLength+1," "), `
                    $this.counters.Item($id)['value'])

        }
        $code += "{0}`n`n" -f ($dash.PadRight($maxLength+5,$dash))

        return $code
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Affiche les compteurs

        IN  : $title    -> Le titre à afficher en entête des compteurs
    #>
    [void] display([string]$title)
    {
        Write-host ($this.getDisplay($title))
    }
}