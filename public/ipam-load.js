function reserveSuccess(ipaddress){
  var button = $("button#"+ipaddress+".btn");
  var element = button[0]
  element.className =
    element.className.replace
      ( /(?:^|\s)btn-danger(?!\S)/g , ' btn-success' );
  element.innerHTML = "true";
  element.onclick = function onclick(event) {unreserveIPAddress(this.id)};
  element.parentNode.parentNode.getElementsByTagName('td')[5].childNodes[0].value = parseInt(element.parentNode.parentNode.getElementsByTagName('td')[5].childNodes[0].value)+1;
  var subnet = button.closest('tbody').attr('id');
  var badge = $('#badge'+subnet);
  var newNum = parseInt($('#badge'+subnet).attr('num'))+1;
  badge.attr('num', newNum);
  badge.text("Allocated: "+newNum);
}


function reserveIPAddress(ipaddress) {
  $.ajax({
    type: "POST",
    url: "/ipam/reserve/" + ipaddress.replace(/\-/g,"."),
    // data:
    headers: { 'x-api-key':'secret'},
    dataType: "json",
    success: reserveSuccess(ipaddress),
    failure: function() { alert("error");},
  });
}

function unreserveSuccess(ipaddress){
  var button = $("button#"+ipaddress+".btn");
  var element = button[0]
  element.className =
    element.className.replace
      ( /(?:^|\s)btn-success(?!\S)/g , ' btn-danger' );
  element.innerHTML = "false";
  element.onclick = function onclick(event) {reserveIPAddress(this.id)};
  var subnet = button.closest('tbody').attr('id');
  var badge = $('#badge'+subnet);
  var newNum = parseInt($('#badge'+subnet).attr('num'))-1;
  badge.attr('num', newNum);
  badge.text("Allocated: "+newNum);
}  

function unreserveIPAddress(ipaddress) {
  $.ajax({
    type: "POST",
    url: "/ipam/unreserve/" + ipaddress.replace(/\-/g,"."),
    // data:
    headers: { 'x-api-key':'secret'},
    dataType: "json",
    success: unreserveSuccess(ipaddress),
    failure: function() { alert("error");},
  });
}

var uniqueDatacenters = new Array();

$.getJSON("datacenters.json?time=" + new Date(), function(jsonData){
  $.each(jsonData, function(i,j){
    uniqueDatacenters.add(j);
  });
  uniqueDatacenters.sort(sort_datacenter);
});

var subnetAllocated = {}

$.getJSON("subnets.json?time=" + new Date(), function(jsonData){
  $.each(jsonData, function(i,j){
    subnetAllocated[j["subnet"]] = j["allocated"];
  });
});


$(document).ready(function () {
  $.ajax({
    url: "/status.json?time=" + new Date(),
    dataType: "json",
    success: function (response, textStatus, jqXHR) {
      var allocatedButtonValue;
      var allocatedButtonType;
      for (var datacenter in uniqueDatacenters) {
        var key = uniqueDatacenters[datacenter];
        var name = key['name'];
        key['subnets'] = key['subnets'].sort(sort_subnet);
	$('#tabs > ul').html(function(i, originalText) {
          return originalText + "<li><a href=\"#"+name+"\"><span class=\"badge pull-right\">" + key['subnets'].length + "</span>"+ name +"</a></li>";});
        $('#tabs > ul').after("<div id=\""+name+"\"><div id=\"accordion-"+name+"\"></div>");
        for (var subnet in key['subnets']) {
          var key2 = key['subnets'][subnet];
          var subn =  key2.replace(/\./g,"-");
	  $('#accordion-'+name).html(function(i,origText){
            return origText + "<h3><span id=\"badge"+subn+"\" class=\"badge pull-right\" num=\""+ subnetAllocated[key2] +"\">Allocated: " + subnetAllocated[key2] + "</span>" + key2 +"</h3> \
              <div id=\""+ subn +"\"> \
              <div class=\"row marketing\"> \
              <table id=\"ipamTable " + subn +"\" class=\"table table-striped\"> \
                <tbody id=\""+subn+"\"> \
                  <tr> \
                    <th>ipaddress</th> \
                      <th>subnet</th> \
                        <th>mask</th> \
                        <th>gateway</th> \
                        <th>nameserver</th> \
                        <th>score</th> \
                        <th>allocated</th> \
                      </tr> \
                    </tbody> \
                  </table> \
                </div> \
              </div>";
          })
        }
      }
      for (var datacenter in uniqueDatacenters){
        var key = uniqueDatacenters[datacenter];
        var name = key['name'];
        $( "#accordion-"+name ).accordion({
          collapsible: true,
          heightStyle: "content"
        });
      }

      $(function() {
        $( "#tabs" ).tabs();
      });

      //sort here if we want them sorted.
      response.sort(sort_ipaddr);

      for (var hostname in response) {
        var key = response[hostname];
        var subnetr = key["subnet"].replace(/\./g,"-");
          if (key["allocated"].indexOf("false") ) {
            var buttonID="id=\"" + key["ipaddress"].replace(/\./g,"-") + "\"";
            allocatedButtonValue = "true";
            allocatedButtonType = "btn btn-success btn-default btn-block";
            $("#" + subnetr+" > div > table > tbody > tr:last").after("<tr><td>" + key["ipaddress"] + "</td><td>" + key["subnet"] + "</td><td>" + key["mask"] + "</td><td>" + key["gateway"] + "</td><td>" + key["nameserver"] + "</td><td>" + "<input type=text value=\"" + key["score"] + " \" disabled>" + "</td><td>" + "<button " + buttonID + " type=button class=\"" + allocatedButtonType + " \" onClick=\"unreserveIPAddress(this.id)\">" + allocatedButtonValue + "</button></td></tr>");
          } else {
            var buttonID="id=\"" + key["ipaddress"].replace(/\./g,"-") + "\"";
            allocatedButtonValue = "false";
            allocatedButtonType = "btn btn-danger btn-default btn-block";
            $("#" + subnetr +" > div > table > tbody > tr:last").after("<tr><td>" + key["ipaddress"] + "</td><td>" + key["subnet"] + "</td><td>" + key["mask"] + "</td><td>" +  key["gateway"] + "</td><td>" + key["nameserver"] + "</td><td>" + "<input type=text value=\"" + key["score"] + " \" disabled>" + "</td><td>" + "<button " + buttonID + " type=button class=\"" + allocatedButtonType + " \" onClick=\"reserveIPAddress(this.id)\">" + allocatedButtonValue + "</button></td></tr>");
          }//end of else statement
      }//end for loop
    },//on seccess
  });//end of ajax
});//end of function


