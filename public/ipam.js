sort_subnet=function(a,b){
  aa = a.split(".");
  bb = b.split(".");

  var resulta = aa[0]*0x1000000 + aa[1]*0x10000 + aa[2]*0x100 + aa[3]*1;
  var resultb = bb[0]*0x1000000 + bb[1]*0x10000 + bb[2]*0x100 + bb[3]*1;

  return resulta-resultb;
};

sort_ipaddr=function(a,b){
  aa = a['ipaddress'].split(".");
  bb = b['ipaddress'].split(".");

  var resulta = aa[0]*0x1000000 + aa[1]*0x10000 + aa[2]*0x100 + aa[3]*1;
  var resultb = bb[0]*0x1000000 + bb[1]*0x10000 + bb[2]*0x100 + bb[3]*1;
  if (a['allocated'] == b['allocated']) {
    return resulta-resultb;
  } else if (a['allocated'] == "true") {
    return -1;
  } else {
    return 1;
  }
};

sort_datacenter = function(a,b){
  if(a['name'] < b['name']){
    return -1;
  } else if(a['name'] > b['name']) {
    return 1;
  } else {
    return 0;
  }
};

function buildNav(opts) {
  $(".nav").html(navHTML);
  switch(opts['page'])
  {
    case "home":
      $('#nav-home').addClass("active");
      break;
    case "ipam":
      $('#nav-ipam').addClass("active");
      break;
    case "dash":
      $('#nav-dash').addClass("active");
      break;
    case "addDC":
      $('#nav-addDC').addClass("active");
      $('#nav-dcNav').addClass("active");
      break;
    case "remDC":
      $('#nav-dcNav').addClass("active");
      $('#nav-remDC').addClass("active");
      break;
    case "addSub":
      $('#nav-subNav').addClass("active");
      $('#nav-addSub').addClass("active");
      break;
    case "remSub":
      $('#nav-subNav').addClass("active");
      $('#nav-remSub').addClass("active");
      break;
    case "login":
      $('#nav-login').addClass("active");
      break;
    case "register":
      $('#nav-login').addClass("active");
      break;
    case "userProf":
      $('#nav-userProf').addClass("active");
      $('#nav-user').addClass("active");
      break;
  }
}

function makeAlert(alertText, alertType){
  var alert = $("<div class=\"alert alert-dismissable\"> \
  <button type=\"button\" class=\"close\" data-dismiss=\"alert\" aria-hidden=\"true\">&times;</button> \
  <span class=\"glyphicon\"></span> " + alertText + " \
  </div>");
  switch (alertType){
    case "success":
      alert.addClass("alert-success");
      alert.find('span').addClass('glyphicon-ok-sign');
      break;
    case "info":
      alert.addClass("alert-info");
      alert.find('span').addClass('glyphicon-info-sign');
      break;
    case "warning":
      alert.addClass("alert-warning");
      alert.find('span').addClass('glyphicon-exclamation-sign');
      break;
    case "danger":
      alert.addClass("alert-danger");
      alert.find('span').addClass('glyphicon-minus-sign');
      break;
  }
  return alert;
}

function showAlerts(alerts) {
  $('.header').after("<div class=\"alerts\"></div>");
  for (var alert in alerts){
    var key = alerts[alert];
    $('.alerts').append(makeAlert(key['text'],key['type']));
  } 
}
