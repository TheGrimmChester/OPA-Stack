// intentional smoke fixture for SAST-lite
function bad(user) {
  eval(user);
  document.body.innerHTML = user;
}
