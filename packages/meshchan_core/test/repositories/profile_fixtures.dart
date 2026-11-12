import 'package:meshchan_core/meshchan_core.dart';

const validBudgets = ProfileBudgets(taskTimeoutSeconds: 3);
final floodRoute = ProfileRoute(routeDescriptor: 0xff);
const validEndpoints = ProfileTestEndpoints(localTestId: 1, peerTestId: 2);

SendProfileParameters sendParameters({
  ProfileBudgets budgets = validBudgets,
  ProfileRoute? route,
  int channel = 3,
  int dataType = 42,
}) => SendProfileParameters(
  budgets: budgets,
  sendChannelIndex: channel,
  route: route ?? floodRoute,
  dataType: dataType,
);
ListenProfileParameters listenParameters({
  ProfileBudgets budgets = validBudgets,
  int channel = 4,
  int? dataType = 42,
  int duration = 8,
  int maxEntries = 128,
}) => ListenProfileParameters(
  budgets: budgets,
  receiveChannelIndex: channel,
  dataType: dataType,
  listenDurationSeconds: duration,
  maxEntries: maxEntries,
);
PingProfileParameters pingParameters({
  ProfileBudgets budgets = validBudgets,
  ProfileRoute? route,
  ProfileTestEndpoints endpoints = validEndpoints,
  int send = 3,
  int receive = 4,
  int response = 8,
  int maxEntries = 128,
}) => PingProfileParameters(
  budgets: budgets,
  sendChannelIndex: send,
  receiveChannelIndex: receive,
  route: route ?? floodRoute,
  endpoints: endpoints,
  responseTimeoutSeconds: response,
  maxEntries: maxEntries,
);
RespondProfileParameters respondParameters({
  ProfileBudgets budgets = validBudgets,
  ProfileRoute? route,
  ProfileTestEndpoints endpoints = validEndpoints,
  int send = 3,
  int receive = 4,
  int duration = 8,
  int maxEntries = 128,
  int maxResponses = 1,
}) => RespondProfileParameters(
  budgets: budgets,
  sendChannelIndex: send,
  receiveChannelIndex: receive,
  route: route ?? floodRoute,
  endpoints: endpoints,
  listenDurationSeconds: duration,
  maxEntries: maxEntries,
  maxResponses: maxResponses,
);
List<ProfileParameters> validParameters() => [
  sendParameters(),
  listenParameters(),
  pingParameters(),
  respondParameters(),
];
ProfileContent profileContent([
  ProfileParameters? p,
  String name = ' same name ',
]) => ProfileContent(
  name: name,
  portHint: ' /local/中文 😀 e\u0301\uFFFD ',
  parameters: p ?? sendParameters(),
);
