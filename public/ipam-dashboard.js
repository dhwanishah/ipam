//This function builds the main interface for the dashboard. It does not add the data fror each of the subnets
$(document).ready(function () {
  $.ajax({
    url: "/datacenters.json?time=" + new Date(),
    dataType: "json",
    success: function (response, textStatus, jqXHR) {
      var uniqueDatacenters = new Array(); //Empty array to hold a list of the datacenters
      $.each(response, function(i,j){ //This adds each of the datacenters names to the array
        uniqueDatacenters.add(j);
      });
      uniqueDatacenters.sort(sort_datacenter); //This sorts the datacenters in alphanumeric order

      //For loop that builds the tabs and accordion sections for datacenters and subnets
      for (var datacenter in uniqueDatacenters) {
        var key = uniqueDatacenters[datacenter];
        var name = key['name']
        key['subnets'] = key['subnets'].sort(sort_subnet);
        $('#tabs > ul').html(function(i, originalText) {
          return originalText + "<li><a href=\"#"+name+"\"><span class=\"badge pull-right\">" + key['subnets'].length + "</span>"+ name +"</a></li>";
        });
        $('#tabs > ul').after("<div id=\""+name+"\"><div id=\"accordion-"+name+"\"></div></div>");

        var uniqueSubnets = key['subnets'];

        for (var subnet in uniqueSubnets) {
          var key2 = uniqueSubnets[subnet];
          var subn =  key2.replace(/\./g,"-");
          $('#accordion-'+name).html(function(i,origText){
            return origText + "<h3>" + key2 +"</h3> \
              <div id=\""+ subn +"\"> \
              <h1>Used: <span class=\"label label-danger\" id=\"usedAddresses\"></span> Free: <span class=\"label label-success\" id=\"freeAddresses\"></h1> \
              </div>";
          })
        }
      }
      //Enables the accordion method and tab method for each datacenter
      for (var datacenter in uniqueDatacenters){
        var key = uniqueDatacenters[datacenter];
        var name = key['name'];
        $("#accordion-"+name).accordion({
          collapsible: true,
          heightStyle: "content"
        });
      }	
      $(function() {
        $( "#tabs" ).tabs();
      });
    },//on seccess
  });//end of ajax
});//end of function

//This function polls subnets.json for the latest numbers concerning free and used IPs for each subnet. It then updates the page accordingly
$(document).ready(function () {
  (function poll () {
    var rand = Math.round(Math.random() * (100 - 700)) + 500;
    setTimeout(function () {
      $.ajax({
        url: "/subnets.json?time=" + new Date(),
        dataType: "json",
        success: function (response, textStatus, jqXHR) {
          for (var subnet in response) {
            var key = response[subnet];
            var totalUsedAddresses = key['allocated'];
            var totalFreeAddresses = key['free'];
            $("#" + key["subnet"].replace(/\./g,"-")+" #usedAddresses").html(totalUsedAddresses), $("#" + key["subnet"].replace(/\./g,"-")+" #freeAddresses").html(totalFreeAddresses);
          }
        },
        error: function (jqXHR, textStatus) {
          //
        },
        complete: function (response) {
          poll();
        },
      });
    }, rand); // poll at random intervals
  })();
});
