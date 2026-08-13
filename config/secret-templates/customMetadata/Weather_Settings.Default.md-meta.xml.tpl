<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata
  xmlns="http://soap.sforce.com/2006/04/metadata"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/2001/XMLSchema"
>
    <label>Default</label>
    <protected>true</protected>
    <values>
        <field>Base_Url__c</field>
        <value
      xsi:type="xsd:string"
    >https://api.openweathermap.org/data/2.5/weather</value>
    </values>
    <values>
        <field>Api_Key__c</field>
        <value xsi:type="xsd:string">${OWM_API_KEY}</value>
    </values>
</CustomMetadata>
